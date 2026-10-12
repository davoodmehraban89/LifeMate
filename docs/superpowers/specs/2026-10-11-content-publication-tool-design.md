# Local content review and publication tooling

This package prepares the existing0013/0015 publication gates for explicit,
reviewable operation. It does not approve school material or deploy anything.

`inspect` reads current catalogue context and hashes. `dry-run` validates an
exact JSON operation against that context in a read-only transaction. `apply`
requires a separate `CONTENT_REVIEW_DATABASE_URL`, an explicit
`CONTENT_REVIEW_SYNTHETIC_ONLY=true` flag and a loopback, explicitly named test
database. Apply further requires a `synthetic-publication:` book fixture and,
for publication, an explicitly marked synthetic reviewer receipt. Existing
research material and the real mathematics pilot remain draft.

Video publication compares the expected metadata material hash and freshly
computed book/unit context hash, then validates every existing full-review,
rights, suitability and question-coverage field. This metadata hash does not
prove the bytes hosted by the provider have remained unchanged. No media is
downloaded, observed or approved by this tool.

Assessment drafting creates a stable UUID/version1 definition or revises an
existing draft/withdrawn definition with the next version and recomputed
question/context hashes. A published definition cannot be edited. Withdrawal
preserves learner attempts and question snapshots. Publishing requires a
complete matching accuracy/objective/suitability receipt and a verified current
book edition. No automated content creation or review claims are made.

All writes share the catalogue-import advisory lock and lock catalogue context
plus target rows. A stable operation UUID and canonical request hash provide
durable exact replay. Replays return the current state: a later withdrawal or
revision dominates an older publish receipt. Stale status/hash/version and
reused operation IDs fail without mutation. Dry-run never inserts audit rows.

Migration0020 adds only `content_publication_audit`, an identifier/hash/status
mutation journal. It contains no feedback summaries, chats, notes, health data
or reviewer prose. The HTTP runtime/backup cannot write it or teaching tables;
only the separate operator/migrator can. No public review/grant endpoint exists.

Tests use a new disposable local PostgreSQL database with stable migrations
0001–0015 plus0020, independent of concurrent schema work. Full integrated
migrations, runtime policy, builds and real device verification remain the
coordinator's checks. Real human content approval remains UNVERIFIED.
