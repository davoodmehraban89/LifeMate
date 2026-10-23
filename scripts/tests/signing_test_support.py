"""Ephemeral, fictional signing fixtures. Never use with owner material."""

from contextlib import contextmanager
from dataclasses import dataclass, field
import hashlib
import os
from pathlib import Path
import secrets
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/java/LifeGuideKeyInspector.java"
JVM_OPTION_VARIABLES = ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "CLASSPATH")


def clean_java_environment():
    return {key: value for key, value in os.environ.items()
            if key.upper() not in JVM_OPTION_VARIABLES}


def request_frame(keystore, alias, store_password, key_password):
    fields = [keystore, alias.encode("utf-8"), store_password.encode("utf-8"),
              key_password.encode("utf-8")]
    return b"LGKI" + b"".join(struct.pack(">I", len(value)) + value for value in fields)


def run_inspector(frame):
    return subprocess.run(
        ["java", "-Xmx96m", "--source", "17", str(HELPER)], input=frame,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        env=clean_java_environment(), check=False,
    )


@dataclass(repr=False)
class SyntheticKeystores:
    directory: Path
    alias: str
    store_password: str = field(repr=False)
    key_password: str = field(repr=False)

    def __post_init__(self):
        self.jks_path = self.directory / "fictional-rsa.jks"
        self.pkcs12_path = self.directory / "fictional-ec.p12"
        self.debug_path = self.directory / "fictional-debug.jks"
        self.cert_only_path = self.directory / "fictional-certificate.jks"
        self.dsa_path = self.directory / "fictional-dsa.jks"
        self.fingerprints = {}

    def keytool(self, *arguments, input_bytes=None):
        environment = clean_java_environment()
        environment["LG_TEST_STORE_PASSWORD"] = self.store_password
        environment["LG_TEST_KEY_PASSWORD"] = self.key_password
        try:
            result = subprocess.run(
                ["keytool", *map(str, arguments)], input=input_bytes,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30, env=environment, check=False,
            )
        except (OSError, subprocess.SubprocessError):
            raise RuntimeError("synthetic keytool invocation failed") from None
        if result.returncode != 0:
            raise RuntimeError("synthetic keytool fixture creation failed")
        return result.stdout

    def create_key(self, path, algorithm, *, debug=False, expired=False):
        pkcs12 = path.suffix == ".p12"
        arguments = [
            "-genkeypair", "-keystore", path, "-storetype", "PKCS12" if pkcs12 else "JKS",
            "-alias", self.alias, "-keyalg", algorithm,
            "-dname", "CN=Android Debug,O=Android,C=US" if debug else "CN=Fictional Signing Fixture,O=Example,C=US",
            "-validity", "1" if expired else "3650", "-noprompt",
            "-storepass:env", "LG_TEST_STORE_PASSWORD",
            "-keypass:env", "LG_TEST_STORE_PASSWORD" if pkcs12 else "LG_TEST_KEY_PASSWORD",
        ]
        if algorithm in ("RSA", "DSA"):
            arguments += ["-keysize", "2048"]
        if expired:
            arguments += ["-startdate", "2020/01/01 00:00:00"]
        self.keytool(*arguments)
        certificate = self.keytool(
            "-exportcert", "-keystore", path, "-alias", self.alias,
            "-storepass:env", "LG_TEST_STORE_PASSWORD",
        )
        self.fingerprints[path] = hashlib.sha256(certificate).hexdigest()
        return certificate

    def mismatched_certificate_store(self):
        """Replace only a public certificate in a disposable encrypted JKS.

        Its unchanged encrypted private key belongs to a different RSA keypair.
        Recompute the legacy JKS integrity checksum so proof is actually reached.
        """
        def certificate(path):
            return self.keytool("-exportcert", "-keystore", path, "-alias", self.alias,
                                "-storepass:env", "LG_TEST_STORE_PASSWORD")

        original = certificate(self.jks_path)
        replacement = certificate(self.debug_path)
        body = self.jks_path.read_bytes()[:-20]
        offset = body.rfind(original)
        if offset < 4 or body[offset - 4:offset] != struct.pack(">I", len(original)):
            raise RuntimeError("synthetic JKS certificate framing unavailable")
        body = (body[:offset - 4] + struct.pack(">I", len(replacement))
                + replacement + body[offset + len(original):])
        integrity = hashlib.sha1(self.store_password.encode("utf-16-be")
                                 + b"Mighty Aphrodite" + body).digest()
        target = self.directory / "fictional-mismatched.jks"
        target.write_bytes(body + integrity)
        return target


@contextmanager
def synthetic_keystores():
    with tempfile.TemporaryDirectory(prefix="lifeguide-synthetic-signing-") as directory:
        fixtures = SyntheticKeystores(
            Path(directory), "fixture-" + secrets.token_hex(8),
            secrets.token_hex(24), secrets.token_hex(24),
        )
        certificate = fixtures.create_key(fixtures.jks_path, "RSA")
        fixtures.create_key(fixtures.pkcs12_path, "EC")
        fixtures.create_key(fixtures.debug_path, "RSA", debug=True)
        fixtures.create_key(fixtures.dsa_path, "DSA")
        fixtures.keytool(
            "-importcert", "-keystore", fixtures.cert_only_path, "-storetype", "JKS",
            "-alias", fixtures.alias, "-noprompt", "-storepass:env", "LG_TEST_STORE_PASSWORD",
            input_bytes=certificate,
        )
        yield fixtures
