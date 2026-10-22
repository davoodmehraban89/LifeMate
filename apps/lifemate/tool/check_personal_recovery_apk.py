"""Inspect the binary manifest of the never-distributed recovery QA APK."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

from check_apk_manifest import manifest_tags

PACKAGE = 'ir.lifeguide.app.personal'
LABEL = 'آزمون بازیابی'


def check(apk, expected_code=None):
    apk = Path(apk)
    with ZipFile(apk) as archive:
        tags = manifest_tags(archive.read('AndroidManifest.xml'))

    def one(name):
        matches = [attributes for tag, attributes in tags if tag == name]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous QA manifest element')
        return matches[0]

    manifest, application, sdk = one('manifest'), one('application'), one('uses-sdk')
    code = manifest.get('versionCode')
    if (manifest.get('package') != PACKAGE or type(code) is not int or code not in (10, 11)
            or (expected_code is not None and code != expected_code)
            or manifest.get('versionName') != f'0.7.2-recovery-qa.{code}'
            or application.get('label') != LABEL):
        raise ValueError('Expected the separate synthetic recovery QA edition')
    if (application.get('debuggable') is not True
            or application.get('allowBackup') is not False
            or application.get('usesCleartextTraffic') is not False):
        raise ValueError('QA debug, backup and network gates are required')
    if sdk.get('minSdkVersion') != 24 or sdk.get('targetSdkVersion') != 36:
        raise ValueError('Unexpected QA SDK versions')
    required = {'android.permission.' + permission for permission in
                ('POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM')}
    allowed = required | {PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
    permissions = {a.get('name') for tag, a in tags if tag.startswith('uses-permission')}
    if not required <= permissions <= allowed:
        raise ValueError('Unexpected QA permissions; INTERNET is forbidden')
    activities = [a for tag, a in tags if tag == 'activity']
    if not any(a.get('name') == 'ir.lifeguide.app.MainActivity' and
               a.get('exported') is True for a in activities):
        raise ValueError('QA must resolve the existing fully qualified activity')
    receivers = [a for tag, a in tags if tag == 'receiver']
    # Exact system-protected dependency also observed in the delivered old APK.
    # This does not permit another exported receiver or relax the reminder gate.
    protected_profile_installer = {
        'name': 'androidx.profileinstaller.ProfileInstallReceiver',
        'permission': 'android.permission.DUMP', 'enabled': True,
        'exported': True, 'directBootAware': False,
    }
    if (not any(a.get('name') == 'ir.lifeguide.app.LocalReminderReceiver'
                and a.get('exported') is False for a in receivers)
            or any(a.get('exported') is True and a != protected_profile_installer
                   for a in receivers)):
        raise ValueError('QA reminder receivers must remain private')
    markers = [a for tag, a in tags if tag == 'meta-data'
               and a.get('name') == 'ir.lifeguide.PERSONAL_RECOVERY_QA']
    if len(markers) != 1 or markers[0].get('value') is not True:
        raise ValueError('Explicit synthetic recovery QA marker is required')
    return {'result': 'PASS', 'package': PACKAGE, 'label': LABEL,
            'versionCode': code, 'versionName': manifest['versionName'],
            'debuggable': True, 'allowBackup': False, 'usesCleartextTraffic': False,
            'internetPermission': False, 'permissions': sorted(permissions),
            'minSdkVersion': 24, 'targetSdkVersion': 36, 'syntheticOnly': True,
            'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
            'limitations': 'Never distribute. Signature and Android lifecycle checked separately.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--expected-code', type=int, choices=(10, 11))
    options = parser.parse_args()
    print(json.dumps(check(options.apk, options.expected_code), ensure_ascii=False, indent=2))
