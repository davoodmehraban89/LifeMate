"""Bounded reads and no-overwrite publication for fictional QA files only."""

import os
from pathlib import Path
import stat
import tempfile

from .common import RecoveryError


def read_bounded(path: Path, limit: int, *, prefix_validator=None) -> bytes:
    """Refuse symlinks/nonregular files; never read unbounded input into memory."""
    path = Path(path)
    descriptor = None
    try:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
            raise RecoveryError("invalid_input_file")
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_size > limit
                or (before.st_dev, before.st_ino) != (info.st_dev, info.st_ino)):
            raise RecoveryError("invalid_input_file")
        with os.fdopen(descriptor, "rb", buffering=0) as stream:
            descriptor = None
            prefix = stream.read(min(limit + 1, 100))
            if prefix_validator is not None:
                prefix_validator(prefix)
            data = prefix + stream.read(limit + 1 - len(prefix))
        if len(data) > limit:
            raise RecoveryError("invalid_input_file")
        return data
    except OSError:
        raise RecoveryError("file_io_error") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def publish_new(destination: Path, payload: bytes) -> None:
    """Link a complete mode0600 temp file atomically; existing paths always win.

    A hard-link-capable local filesystem is required. No overwrite fallback is
    permitted. fsync completes before publication; power-loss durability of the
    directory and platform-specific filesystem behavior are not asserted here.
    """
    destination = Path(destination)
    temporary = None
    descriptor = None
    try:
        if os.path.lexists(destination):
            raise RecoveryError("destination_exists")
        descriptor, name = tempfile.mkstemp(prefix=".lifeguide-qa-", dir=destination.parent)
        temporary = Path(name)
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = None
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, destination)
    except FileExistsError:
        raise RecoveryError("destination_exists") from None
    except OSError:
        raise RecoveryError("file_io_error") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary is not None:
            temporary.unlink(missing_ok=True)
