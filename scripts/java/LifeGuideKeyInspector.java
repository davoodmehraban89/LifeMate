import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.cert.CertificateExpiredException;
import java.security.cert.CertificateNotYetValidException;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.HexFormat;
import javax.naming.NamingEnumeration;
import javax.naming.directory.Attribute;
import javax.naming.ldap.LdapName;
import javax.naming.ldap.Rdn;

/** Reads one bounded stdin frame; emits only public facts or a fixed refusal. */
public final class LifeGuideKeyInspector {
    private static final int MAX_STORE_BYTES = 2 * 1024 * 1024;

    private static final class Refusal extends Exception {
        final String reason;
        Refusal(String reason) { this.reason = reason; }
    }

    private static final class Request implements AutoCloseable {
        byte[] keystore;
        byte[] aliasBytes;
        byte[] storePasswordBytes;
        byte[] keyPasswordBytes;
        String alias;
        char[] storePassword;
        char[] keyPassword;

        public void close() {
            wipe(keystore);
            wipe(aliasBytes);
            wipe(storePasswordBytes);
            wipe(keyPasswordBytes);
            if (storePassword != null) Arrays.fill(storePassword, '\0');
            if (keyPassword != null) Arrays.fill(keyPassword, '\0');
        }
    }

    private static void wipe(byte[] bytes) {
        if (bytes != null) Arrays.fill(bytes, (byte) 0);
    }

    private static byte[] readField(DataInputStream input, int maximum) throws IOException, Refusal {
        int length = input.readInt();
        // Negative signed values represent unsigned lengths above 2 GiB.
        if (length < 1 || length > maximum) throw new Refusal("invalid_request");
        byte[] bytes = new byte[length];
        try {
            input.readFully(bytes);
            return bytes;
        } catch (IOException exception) {
            wipe(bytes);
            throw exception;
        }
    }

    private static char[] decodeUtf8(byte[] bytes) throws CharacterCodingException {
        CharBuffer decoded = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes));
        try {
            char[] characters = new char[decoded.remaining()];
            decoded.get(characters);
            return characters;
        } finally {
            if (decoded.hasArray()) Arrays.fill(decoded.array(), '\0');
        }
    }

    private static char[] decodePassword(byte[] bytes) throws Refusal, CharacterCodingException {
        char[] characters = decodeUtf8(bytes);
        for (char character : characters) {
            if (character == '\0' || character == '\r' || character == '\n') {
                Arrays.fill(characters, '\0');
                throw new Refusal("invalid_request");
            }
        }
        return characters;
    }

    private static Request readRequest() throws Refusal {
        Request request = new Request();
        try {
            DataInputStream input = new DataInputStream(System.in);
            if (input.readInt() != 0x4c474b49) throw new Refusal("invalid_request");
            request.keystore = readField(input, MAX_STORE_BYTES);
            request.aliasBytes = readField(input, 256);
            request.storePasswordBytes = readField(input, 4096);
            request.keyPasswordBytes = readField(input, 4096);
            if (input.read() != -1) throw new Refusal("invalid_request");
            char[] alias = decodeUtf8(request.aliasBytes);
            try {
                request.alias = new String(alias);
            } finally {
                Arrays.fill(alias, '\0');
            }
            request.storePassword = decodePassword(request.storePasswordBytes);
            request.keyPassword = decodePassword(request.keyPasswordBytes);
            wipe(request.storePasswordBytes);
            wipe(request.keyPasswordBytes);
            return request;
        } catch (IOException | Refusal exception) {
            request.close();
            throw new Refusal("invalid_request");
        }
    }

    private static KeyStore loadStore(Request request) throws Refusal {
        for (String format : new String[] {"JKS", "PKCS12"}) {
            try {
                KeyStore store = KeyStore.getInstance(format);
                store.load(new ByteArrayInputStream(request.keystore), request.storePassword);
                return store;
            } catch (Exception exception) {
                // Try only the two supported formats, without exposing provider errors.
            }
        }
        throw new Refusal("keystore_unreadable");
    }

    private static KeyStore.PrivateKeyEntry privateEntry(KeyStore store, Request request) throws Refusal {
        KeyStore.PasswordProtection protection = new KeyStore.PasswordProtection(request.keyPassword);
        try {
            if (!store.entryInstanceOf(request.alias, KeyStore.PrivateKeyEntry.class)) {
                throw new Refusal("private_key_unavailable");
            }
            KeyStore.Entry entry = store.getEntry(request.alias, protection);
            if (!(entry instanceof KeyStore.PrivateKeyEntry)) {
                throw new Refusal("private_key_unavailable");
            }
            return (KeyStore.PrivateKeyEntry) entry;
        } catch (Exception exception) {
            throw new Refusal("private_key_unavailable");
        } finally {
            try { protection.destroy(); } catch (Exception ignored) { }
        }
    }

    private static void proveKey(PrivateKey key, X509Certificate certificate) throws Refusal {
        String algorithm;
        switch (key.getAlgorithm()) {
            case "RSA": algorithm = "SHA256withRSA"; break;
            case "EC": algorithm = "SHA256withECDSA"; break;
            default: throw new Refusal("unsupported_key_algorithm");
        }
        byte[] challenge = new byte[32];
        byte[] proof = null;
        try {
            new SecureRandom().nextBytes(challenge);
            Signature signer = Signature.getInstance(algorithm);
            signer.initSign(key);
            signer.update(challenge);
            proof = signer.sign();
            Signature verifier = Signature.getInstance(algorithm);
            verifier.initVerify(certificate.getPublicKey());
            verifier.update(challenge);
            if (!verifier.verify(proof)) throw new Refusal("key_proof_failed");
        } catch (Exception exception) {
            throw new Refusal("key_proof_failed");
        } finally {
            wipe(challenge);
            wipe(proof);
        }
    }

    private static boolean debugCertificate(X509Certificate certificate) throws Exception {
        LdapName name = new LdapName(certificate.getSubjectX500Principal().getName());
        for (Rdn rdn : name.getRdns()) {
            // A multi-valued RDN's primary type may be C/OU even when it has CN.
            NamingEnumeration<? extends Attribute> attributes = rdn.toAttributes().getAll();
            try {
                while (attributes.hasMore()) {
                    Attribute attribute = attributes.next();
                    if (!"CN".equalsIgnoreCase(attribute.getID())) continue;
                    for (int index = 0; index < attribute.size(); index++) {
                        if ("Android Debug".equalsIgnoreCase(String.valueOf(attribute.get(index)))) return true;
                    }
                }
            } finally {
                attributes.close();
            }
        }
        return false;
    }

    private static String inspect(Request request) throws Exception {
        KeyStore.PrivateKeyEntry entry = privateEntry(loadStore(request), request);
        if (!(entry.getCertificate() instanceof X509Certificate)) throw new Refusal("inspection_failed");
        X509Certificate certificate = (X509Certificate) entry.getCertificate();
        proveKey(entry.getPrivateKey(), certificate);
        boolean valid = true;
        try {
            certificate.checkValidity();
        } catch (CertificateExpiredException | CertificateNotYetValidException exception) {
            valid = false;
        }
        String fingerprint = HexFormat.of().formatHex(
            MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
        return "{\"schemaVersion\":1,\"status\":\"INSPECTED\",\"certificateSha256\":\""
            + fingerprint + "\",\"debugCertificate\":" + debugCertificate(certificate)
            + ",\"privateKeyProof\":true,\"certificateCurrentlyValid\":" + valid + "}";
    }

    public static void main(String[] arguments) {
        String result;
        int exitCode;
        try {
            if (arguments.length != 0) throw new Refusal("invalid_request");
            try (Request request = readRequest()) {
                result = inspect(request);
            }
            exitCode = 0;
        } catch (Exception | LinkageError exception) {
            String reason = exception instanceof Refusal ? ((Refusal) exception).reason : "inspection_failed";
            result = "{\"schemaVersion\":1,\"status\":\"REFUSED\",\"reason\":\"" + reason + "\"}";
            exitCode = 2;
        }
        System.out.println(result);
        System.exit(exitCode);
    }
}
