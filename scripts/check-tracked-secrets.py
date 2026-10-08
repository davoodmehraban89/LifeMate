#!/usr/bin/env python3
"""Check tracked files only; synthetic fixture literals are not live secrets."""
import re
import subprocess
from pathlib import Path

files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
patterns = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{30,}|sk_live_[A-Za-z0-9]{20,}')
errors = []
for name in filter(None, files):
    p = Path(name)
    if not p.is_file(): continue
    if (p.name.startswith('.env') and p.name != '.env.example') or p.suffix.lower() in {'.jks', '.keystore', '.dump', '.p12', '.pfx'}:
        errors.append(f'{name}: private artifact must not be tracked')
    if p.stat().st_size > 10_000_000: continue
    if patterns.search(p.read_bytes()): errors.append(f'{name}: high-confidence secret pattern (content withheld)')
if errors: raise SystemExit('\n'.join(errors))
print('Tracked-file credential/artifact scan passed; this is not a complete secret audit.')
