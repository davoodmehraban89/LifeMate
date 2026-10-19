#!/usr/bin/env python3
"""Inspect the device-only APK binary manifest. Signature/install are separate."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

from check_apk_manifest import manifest_tags

PACKAGE = 'ir.lifeguide.app.device'
LABEL = 'لایف‌گاید شخصی'


def check(apk):
    apk = Path(apk)
    with ZipFile(apk) as archive:
        tags = manifest_tags(archive.read('AndroidManifest.xml'))
    manifest = next(a for tag, a in tags if tag == 'manifest')
    application = next(a for tag, a in tags if tag == 'application')
    sdk = next(a for tag, a in tags if tag == 'uses-sdk')
    permissions = {a.get('name') for tag, a in tags if tag.startswith('uses-permission')}
    allowed = {'android.permission.POST_NOTIFICATIONS',
               'android.permission.RECEIVE_BOOT_COMPLETED',
               'android.permission.SCHEDULE_EXACT_ALARM',
               PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
    if manifest.get('package') != PACKAGE or application.get('label') != LABEL:
        raise ValueError('Expected the separate LifeGuide personal device edition')
    if manifest.get('versionName') != '0.7.2-personal.1' or manifest.get('versionCode') != 9:
        raise ValueError('Unexpected personal APK version')
    if (application.get('debuggable') is not True or
            application.get('allowBackup') is not False or
            application.get('usesCleartextTraffic') is not False):
        raise ValueError('Personal debug, backup and network gates are required')
    if not permissions <= allowed or not (allowed - {PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}) <= permissions:
        raise ValueError('Unexpected or missing device edition permissions; INTERNET is forbidden')
    if sdk.get('minSdkVersion') != 24 or sdk.get('targetSdkVersion') != 36:
        raise ValueError('Unexpected Android SDK versions')
    activities = [a for tag, a in tags if tag == 'activity']
    if not any(a.get('name') == 'ir.lifeguide.app.MainActivity' and a.get('exported') is True for a in activities):
        raise ValueError('Personal APK must resolve the existing fully-qualified MainActivity')
    receivers = [a for tag, a in tags if tag == 'receiver']
    if not any(a.get('name') == 'ir.lifeguide.app.LocalReminderReceiver' and a.get('exported') is False for a in receivers):
        raise ValueError('Reminder receiver must remain private')
    return {'result': 'PASS', 'package': PACKAGE, 'label': LABEL,
            'versionName': manifest['versionName'], 'versionCode': 9,
            'debuggable': True, 'allowBackup': False, 'usesCleartextTraffic': False,
            'internetPermission': False, 'permissions': sorted(permissions),
            'minSdkVersion': 24, 'targetSdkVersion': 36,
            'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
            'limitations': 'Debug initial personal edition; signature and actual lifecycle checked separately.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    options = parser.parse_args()
    print(json.dumps(check(options.apk), ensure_ascii=False, indent=2))
