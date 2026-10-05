# Production Checklist

A public production release is a separate approval event. Do not infer approval from completion of Phase 5.

- [ ] All GitHub CI jobs green at the exact release commit.
- [ ] Staging `/live`, `/ready`, `/health` green and critical smoke flows verified.
- [ ] Current database backup exists and a recent restore drill passed.
- [ ] Rollback target and operator are identified.
- [ ] Secrets are configured only in platform secret management.
- [ ] CORS origins and public application URL are production-specific.
- [ ] Rate-limit defaults reviewed for expected traffic and single/multi-instance topology.
- [ ] Alert destinations exist for readiness failure, elevated 5xx and sustained 429 anomalies.
- [ ] Minor-sensitive external AI remains disabled until legal/guardian-consent, provider privacy/retention, safety taxonomy and emergency-resource gates pass.
- [ ] Voice transmission remains disabled until voice-provider privacy review passes.
- [ ] Wellbeing retention/export/deletion policy is approved before public exposure.
- [ ] Release version and changelog are final.
- [ ] Explicit production deployment approval has been received.
