# Content publication tool execution

1. RED: exact manifest/receipt/input and local-only connection tests; PostgreSQL
   dry-run purity, stale context/hash, missing full-review flags and replay tests.
2. Add0020 identifier/hash-only audit journal and no new HTTP router.
3. Implement current-context inspection, full gate validation, catalogue-lock
   transactions and synthetic-fixture-only application/withdrawal.
4. Add original assessment draft/revision with stable IDs, recomputed hashes,
   published-definition protection and retained attempt snapshots.
5. Implement a CLI that reads JSON from a file, prints safe structural receipts
   and never logs credentials or raw driver errors. No media fetching occurs.
6. GREEN: focused Node22 real PostgreSQL tests, scoped syntax, actual CLI
   invocation, repeated operation replay, runtime/backup denial and no audit
   text fields. Coordinator runs integrated migrations/suite/role restore.
7. Document exact manual inspect/dry-run commands and explain that this build's
   apply mode supports synthetic fixtures only. Keep pilot review:null/draft.
