# Local signing preflight — preparation only

Scope: a read-only host tool for a future, explicitly chosen owner-local key
inspection. This packet implements and exercises it with ephemeral synthetic
keys only. ADR0018's preparation-only boundary is unchanged. It does not create
an owner key, configure signing, transfer child data or unlock APK delivery.

## Problem and approach

The installed APK's public signer is recorded in the delivered baseline. Its
private key's availability is UNVERIFIED. Existing release automation signs the
online application on GitHub; it is unsuitable for inspecting an offline owner's
key locally. Parsing verbose keytool output could expose certificate identity.
Use Python for explicit CLI/guards and a small local JDK17+ helper for typed
KeyStore inspection instead. No network, device or signing/build commands.

Default `check` reads only the public baseline and checks Java availability,
including compiling the fixed helper with empty input (no key inspection).
`inspect` requires an explicit file, alias, acknowledgement and a non-echoing
interactive terminal. Passwords have no argument/environment interface. The
tool never searches for keys, copies/exports/generates one, prints identities,
writes reports automatically, or modifies the selected file. Output is JSON
containing only a fingerprint, public compatibility facts and fixed codes.

The encrypted file is read once with the existing bounded no-follow regular-file
reader (2 MiB maximum). A local subprocess receives bounded binary stdin, no
secret/path/alias arguments: `LGKI`, then four unsigned big-endian 32-bit lengths
and their byte strings: keystore, UTF-8 alias (1–256 bytes), store password
(1–4096 bytes), key password (1–4096 bytes). EOF required. Passwords reject NUL,
CR and LF. Java supports JKS and PKCS12; it decrypts a PrivateKeyEntry, signs a
random internal challenge and verifies it with the certificate's public key.
RSA/SHA256withRSA and EC/SHA256withECDSA only. Challenge/signature/private key
are never output. Fixed helper JSON v1 has `certificateSha256`, `debugCertificate`,
`privateKeyProof` (true) and `certificateCurrentlyValid` booleans, or a refusal
code. Python validates the exact schema. Child timeout 30 seconds, heap 96 MiB.

Comparison is against the reviewed delivered baseline, with no caller override.
A matching debug signer remains a compatibility fact; the tool must separately
refuse to label it production-ready. Every report keeps `delivery: BLOCKED`,
`releaseReadiness: UNVERIFIED`, `installedDeviceVerification: UNVERIFIED` and
`dataPreservation: UNVERIFIED`. A successful inspection is not release approval.

## Acceptance and boundaries

- Real temporary JKS/PKCS12 fixtures: repeated inspection, encrypted fixture copy,
  wrong store/key passwords, missing/certificate-only aliases, corrupt input,
  debug certificate. Source bytes remain equal. Fixture identity is fictional.
- CLI acknowledgement/TTY before file access; malformed arguments/errors, helper
  corruption/timeout cannot leak canary passwords, paths, aliases or raw output.
- No symlink, FIFO, directory, oversized file or baseline override. No plaintext
  file writes or secret arguments. JVM environment options that can inject
  agents/options are removed from the helper child environment.
- Ubuntu/Windows CI uses ephemeral test keys only and uploads no key material.
- Windows interactive prompts/ACL, owner keys/device, actual signing/upgrade,
  data transfer and Android acceptance remain UNVERIFIED until separately done.
- Python/JVM memory zeroization, hostile administrators/JDKs, parent-directory
  symlink confinement and adversarial local filesystems are not guaranteed.

No Flutter/backend/Gradle/package/version/workflow-delivery-policy changes.
No merge, deploy, DNS, public release, owner key operation or real-data operation.
