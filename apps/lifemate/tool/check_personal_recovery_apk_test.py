"""Synthetic manifest contracts; no actual APK installation is inferred."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

import check_personal_recovery_apk as subject


class RecoveryManifestTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.apk = Path(directory.name) / 'qa.apk'
        with ZipFile(self.apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'parser fixture')
        self.tags = [
            ('manifest', {'package': 'ir.lifeguide.app.personal', 'versionCode': 10,
                          'versionName': '0.7.2-recovery-qa.10'}),
            ('application', {'label': 'آزمون بازیابی', 'debuggable': True,
                             'allowBackup': False, 'usesCleartextTraffic': False}),
            ('uses-sdk', {'minSdkVersion': 24, 'targetSdkVersion': 36}),
            ('activity', {'name': 'ir.lifeguide.app.MainActivity', 'exported': True}),
            ('receiver', {'name': 'ir.lifeguide.app.LocalReminderReceiver', 'exported': False}),
            ('meta-data', {'name': 'ir.lifeguide.PERSONAL_RECOVERY_QA', 'value': True}),
        ] + [('uses-permission', {'name': 'android.permission.' + name}) for name in
             ('POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM')]

    def check(self, code=None):
        with patch.object(subject, 'manifest_tags', return_value=self.tags):
            return subject.check(self.apk, expected_code=code)

    def test_exact_qa_identity_and_higher_version(self):
        self.assertEqual(self.check()['versionCode'], 10)
        self.tags[0][1].update(versionCode=11, versionName='0.7.2-recovery-qa.11')
        self.assertEqual(self.check()['versionCode'], 11)
        with self.assertRaises(ValueError):
            self.check(10)

    def test_rejects_product_identity_permissions_and_missing_qa_marker(self):
        for index, key, value in ((0, 'package', 'ir.lifeguide.app.device'),
                                  (0, 'versionCode', 12), (1, 'label', 'لایف‌گاید'),
                                  (1, 'debuggable', False), (1, 'allowBackup', True),
                                  (1, 'usesCleartextTraffic', True), (2, 'targetSdkVersion', 35),
                                  (2, 'minSdkVersion', 23), (3, 'name', '.MainActivity'),
                                  (4, 'exported', True), (5, 'value', False)):
            with self.subTest(key=key, value=value):
                old = self.tags[index][1][key]
                self.tags[index][1][key] = value
                with self.assertRaises(ValueError):
                    self.check()
                self.tags[index][1][key] = old
        self.tags.append(('uses-permission', {'name': 'android.permission.INTERNET'}))
        with self.assertRaises(ValueError):
            self.check()
        self.tags.pop()
        self.tags.pop(5)
        with self.assertRaises(ValueError):
            self.check()

    def test_duplicate_critical_manifest_tags_refused(self):
        self.tags.append(('manifest', self.tags[0][1].copy()))
        with self.assertRaises(ValueError):
            self.check()


    def test_existing_profileinstaller_requires_exact_system_permission(self):
        # Observed in the exact delivered original APK after baseline SHA check.
        protected = {'name': 'androidx.profileinstaller.ProfileInstallReceiver',
                     'permission': 'android.permission.DUMP', 'enabled': True,
                     'exported': True, 'directBootAware': False}
        self.tags.append(('receiver', protected))
        self.assertEqual(self.check()['result'], 'PASS')
        for key, value in (('permission', None), ('permission', 'android.permission.INTERNET'),
                           ('name', 'unexpected.ExportedReceiver')):
            original = protected[key]
            protected[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.check()
            protected[key] = original


if __name__ == '__main__':
    unittest.main()
