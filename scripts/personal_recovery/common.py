"""Shared limits and sanitized failures for the synthetic recovery test kit."""

MAX_PAYLOAD_BYTES = 8 * 1024 * 1024
MAX_ROWS = 20_000
SCHEMA_VERSION = 1
FIXTURE_APPLICATION_ID = 0x4C475146


class RecoveryError(Exception):
    """A reason code safe to show without exposing payloads or credentials."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)
