"""Bounded authenticated envelopes for the synthetic recovery preparation tool.

Version 1 fixes the KDF parameters; archive bytes cannot choose their cost.
This module only handles in-memory bytes and never logs or writes their content.
"""

import os

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

from .common import MAX_PAYLOAD_BYTES, RecoveryError


_MAGIC = b"LGRF\x01"
_SALT_BYTES = 16
_NONCE_BYTES = 12
_TAG_BYTES = 16
_HEADER_BYTES = len(_MAGIC) + _SALT_BYTES + _NONCE_BYTES
_MIN_ARCHIVE_BYTES = _HEADER_BYTES + _TAG_BYTES
_MAX_ARCHIVE_BYTES = MAX_PAYLOAD_BYTES + _MIN_ARCHIVE_BYTES


def _password_bytes(passphrase: str) -> bytes:
    # Bound characters before encoding, then enforce the UTF-8 byte limit.
    if not isinstance(passphrase, str) or not 12 <= len(passphrase) <= 1024:
        raise RecoveryError("invalid_passphrase")
    try:
        encoded = passphrase.encode("utf-8")
    except UnicodeEncodeError:
        raise RecoveryError("invalid_passphrase") from None
    if len(encoded) > 1024:
        raise RecoveryError("invalid_passphrase")
    return encoded


def _derive_key(password: bytes, salt: bytes) -> bytes:
    return Scrypt(salt=salt, length=32, n=32768, r=8, p=1).derive(password)


def seal(payload: bytes, passphrase: str) -> bytes:
    """Encrypt up to 8 MiB using a fresh salt and nonce for each envelope."""
    if not isinstance(payload, bytes) or len(payload) > MAX_PAYLOAD_BYTES:
        raise RecoveryError("invalid_payload")
    password = _password_bytes(passphrase)
    salt = os.urandom(_SALT_BYTES)
    nonce = os.urandom(_NONCE_BYTES)
    header = _MAGIC + salt + nonce
    ciphertext = AESGCM(_derive_key(password, salt)).encrypt(nonce, payload, header)
    return header + ciphertext


def open_archive(archive: bytes, passphrase: str) -> bytes:
    """Authenticate before returning plaintext; reject invalid bounds before KDF."""
    if (
        not isinstance(archive, bytes)
        or not _MIN_ARCHIVE_BYTES <= len(archive) <= _MAX_ARCHIVE_BYTES
        or archive[: len(_MAGIC)] != _MAGIC
    ):
        raise RecoveryError("invalid_archive")
    password = _password_bytes(passphrase)
    salt = archive[len(_MAGIC) : len(_MAGIC) + _SALT_BYTES]
    nonce = archive[len(_MAGIC) + _SALT_BYTES : _HEADER_BYTES]
    try:
        return AESGCM(_derive_key(password, salt)).decrypt(
            nonce, archive[_HEADER_BYTES:], archive[:_HEADER_BYTES]
        )
    except InvalidTag:
        raise RecoveryError("archive_authentication_failed") from None
