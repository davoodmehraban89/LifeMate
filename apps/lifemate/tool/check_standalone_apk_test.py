"""Packaging gates; test manifests are synthetic, not an APK build."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

import check_standalone_apk as subject


class StandaloneManifestTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / 'LifeGuide.apk'
        with ZipFile(self.apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'synthetic parser fixture')
        self.tags = [
            ('manifest', {'package': 'ir.lifeguide.app.device',
                          'versionName': '0.7.2-personal.1', 'versionCode': 9}),
            ('uses-sdk', {'minSdkVersion': 24, 'targetSdkVersion': 36}),
            ('application', {'label': 'لایف‌گاید شخصی', 'debuggable': True,
                             'allowBackup': False, 'usesCleartextTraffic': False}),
            ('activity', {'name': 'ir.lifeguide.app.MainActivity', 'exported': True}),
            ('receiver', {'name': 'ir.lifeguide.app.LocalReminderReceiver', 'exported': False}),
            ('uses-permission', {'name': 'android.permission.POST_NOTIFICATIONS'}),
            ('uses-permission', {'name': 'android.permission.RECEIVE_BOOT_COMPLETED'}),
            ('uses-permission', {'name': 'android.permission.SCHEDULE_EXACT_ALARM'}),
        ]

    def check(self):
        with patch.object(subject, 'manifest_tags', return_value=self.tags):
            return subject.check(self.apk)

    def test_separate_debug_device_edition_has_no_internet(self):
        result = self.check()
        self.assertEqual(result['result'], 'PASS')
        self.assertEqual(result['package'], 'ir.lifeguide.app.device')
        self.assertIs(result['internetPermission'], False)
        self.assertEqual(len(result['sha256']), 64)

    def test_online_identity_and_wrong_main_activity_are_rejected(self):
        self.tags[0][1]['package'] = 'ir.lifeguide.app'
        with self.assertRaises(ValueError):
            self.check()
        self.tags[0][1]['package'] = 'ir.lifeguide.app.device'
        self.tags[3][1]['name'] = 'ir.lifeguide.app.device.MainActivity'
        with self.assertRaises(ValueError):
            self.check()

    def test_internet_and_unexpected_permissions_are_rejected(self):
        for permission in ('android.permission.INTERNET', 'android.permission.READ_CONTACTS'):
            with self.subTest(permission=permission):
                self.tags.append(('uses-permission', {'name': permission}))
                with self.assertRaises(ValueError):
                    self.check()
                self.tags.pop()

    def test_backup_cleartext_exported_receiver_or_wrong_version_are_rejected(self):
        for index, key, value in ((2, 'allowBackup', True),
                                  (2, 'usesCleartextTraffic', True),
                                  (2, 'debuggable', False),
                                  (4, 'exported', True), (0, 'versionCode', 8)):
            old = self.tags[index][1][key]
            with self.subTest(key=key):
                self.tags[index][1][key] = value
                with self.assertRaises(ValueError):
                    self.check()
            self.tags[index][1][key] = old


if __name__ == '__main__':
    unittest.main()
