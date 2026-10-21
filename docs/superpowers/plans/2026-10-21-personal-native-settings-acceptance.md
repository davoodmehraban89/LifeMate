# Personal notification settings — synthetic Android acceptance

Owner priority: finish the offline planner before online work; preserve installed
data and verify reminders. This PR changes only developer test tools and docs.
Base: PR41 /76efe36. No new product/privacy/hosting decision is selected.

The gap is specific: local widget tests mock MethodChannel and existing emulator
tests never invoke the new native settings method. They cannot prove which
Android settings screen opens or that the native OFF choice survives it.

Acceptance:

1. Keep all existing fresh API35 emulator, explicit serial, same-certificate,
   no-existing-package and no-real-device safety gates. Never distribute fixture.
2. After the existing real SQLite/archive/notification/OFF checks, a debug-only
   fixture mode invokes the product port's openNotificationSettings method.
3. Independent UIAutomator output must show the fixed Persian channel title
   owned by com.android.settings. A matching label from another app is rejected.
4. Return with Android Back, then close/relaunch/read SQLite and native state:
   OFF remains OFF, no pending/delivered notification and all existing SQL audit
   checks pass. No permission/enable/record write belongs to the settings mode.
5. Sanitized receipt records assertions only. No raw XML, database, task content,
   key, OTP or real device information enters artifacts.

RED: add host parser/orchestration rejection tests first, run and observe failure.
GREEN: minimally extend the existing isolated fixture/runner, retaining previous
alarms/SQLite gates. Run host suite, Flutter/analyzer/format as appropriate; open
a separate draft PR and let real CI execute Android. Keep failures visible.

Limitations remain explicit: this complements mocked button tests; it is not a
physical-phone sound/Doze/reboot test, an OEM-fallback test, or exact previously
delivered APK → new APK/default-database upgrade acceptance. The existing upload
hold is untouched. No keys, uninstall, clear-data, merge, deploy or DNS changes.
