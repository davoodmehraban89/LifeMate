#!/usr/bin/env python3
"""Inventory every remaining legacy-name text occurrence in tracked source."""
import argparse
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
rows, errors = [], []
active_docs = {'README.md', 'AGENTS.md', 'PROJECT_STATE.md', 'CHANGELOG.md'}
for name in filter(None, files):
    p = Path(name)
    if not p.is_file() or name == 'docs/audits/2026-10-08-naming.md': continue
    raw = p.read_bytes()
    if b'\0' in raw: continue
    for line_no, line in enumerate(raw.decode('utf-8', errors='replace').splitlines(), 1):
        if not re.search('lifemate', line, re.I): continue
        historical = name.startswith(('docs/history/', 'docs/final/', 'docs/plans/', 'docs/ux/', 'docs/product/', 'docs/quality/', 'docs/safety/', 'docs/architecture/', 'docs/superpowers/')) or name == 'docs/ROADMAP.md' or name.startswith('docs/audits/') or name in {'docs/decisions/0005-backend-supabase.md', 'docs/decisions/0006-provider-neutral-postgresql-backend.md'}
        internal = re.search(r'LifeMateApp|_LifeMateAppState|davoodmehraban89/LifeMate|/LifeMate|apps/lifemate|package:lifemate|lifemate[-_]|\blifemate\b|LIFEMATE', line)
        if historical:
            category, reason = 'historical — keep', 'snapshot/previous decision; not current deployment evidence'
        elif internal:
            category, reason = 'protocol-sensitive/internal — keep', 'repository/path/package/resource or JWT/service/test compatibility'
        else:
            category, reason = 'user-facing — change', 'legacy display name requires review'
            errors.append(f'{name}:{line_no}')
        # Display declarations must never hide behind adjacent internal paths.
        if name.startswith(('apps/lifemate/lib/', 'apps/lifemate/web/', '.github/workflows/')) and re.search(r"['\"][^'\"]*\bLifeMate\b[^'\"]*['\"]", line) and not re.search(r'LifeMateApp|package:', line):
            category, reason = 'user-facing — change', 'legacy label/literal in active client or workflow'
            errors.append(f'{name}:{line_no}')
        snippet = line.strip().replace('|', '\\|').replace('`', "'")[:220]
        rows.append(f'| {name}:{line_no} | {category} | {reason} | {snippet} |')
if args.check:
    if errors: raise SystemExit('Unchanged user-facing legacy name:\n' + '\n'.join(sorted(set(errors))))
    print(f'Naming audit passed: {len(rows)} retained text occurrences classified; binary fonts/icons excluded.')
else:
    Path('docs/audits/2026-10-08-naming.md').write_text('# LifeGuide — remaining legacy-name inventory\n\nGenerated with `python3 scripts/audit-naming.py` from tracked source. Product displays are LifeGuide; repository/schema/JWT/internal compatibility and historical evidence retain their original names. Rows classify every remaining case-insensitive legacy-name line; repeated occurrences on that line share its classification. Binary fonts/icons are not text. This inventory excludes itself.\n\n| Location | Classification | Reason | Source excerpt |\n| --- | --- | --- | --- |\n' + '\n'.join(rows) + '\n')
    print(f'Wrote {len(rows)} classified rows; {len(set(errors))} display-name review items.')
