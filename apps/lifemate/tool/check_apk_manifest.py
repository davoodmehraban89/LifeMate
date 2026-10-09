#!/usr/bin/env python3
"""Check the actual APK binary manifest; this does not verify its signature/install."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
from zipfile import ZipFile


def manifest_tags(data):
    def u16(offset):
        return struct.unpack_from('<H', data, offset)[0]

    def u32(offset):
        return struct.unpack_from('<I', data, offset)[0]

    def encoded_length(offset, wide=False):
        first = u16(offset) if wide else data[offset]
        high = 0x8000 if wide else 0x80
        shift = 16 if wide else 8
        step = 2 if wide else 1
        if first & high:
            second = u16(offset + step) if wide else data[offset + step]
            return ((first & (high - 1)) << shift) | second, offset + 2 * step
        return first, offset + step

    if u16(0) != 3 or u32(4) != len(data):
        raise ValueError('Expected a binary Android XML manifest')
    strings, tags, offset = [], [], u16(2)
    while offset < len(data):
        kind, header_size, size = struct.unpack_from('<HHI', data, offset)
        if size < header_size or offset + size > len(data):
            raise ValueError('Invalid Android XML chunk')
        if kind == 1:
            count, _, flags, start, _ = struct.unpack_from('<IIIII', data, offset + 8)
            for index in range(count):
                position = offset + start + u32(offset + header_size + index * 4)
                if flags & 0x100:
                    _, position = encoded_length(position)
                    length, position = encoded_length(position)
                    value = data[position:position + length].decode('utf-8')
                else:
                    length, position = encoded_length(position, wide=True)
                    value = data[position:position + 2 * length].decode('utf-16-le')
                strings.append(value)
        elif kind == 0x102:
            extension = offset + header_size
            tag = strings[u32(extension + 4)]
            attr_start, attr_size, attr_count = struct.unpack_from('<HHH', data, extension + 8)
            attributes = {}
            for index in range(attr_count):
                position = extension + attr_start + index * attr_size
                name, raw = strings[u32(position + 4)], u32(position + 8)
                value_type, value = data[position + 15], u32(position + 16)
                if raw != 0xffffffff:
                    decoded = strings[raw]
                elif value_type == 3:
                    decoded = strings[value]
                elif value_type == 18:
                    decoded = bool(value)
                else:
                    decoded = value
                attributes[name] = decoded
            tags.append((tag, attributes))
        offset += size
    return tags


def check(apk, mode):
    with ZipFile(apk) as archive:
        tags = manifest_tags(archive.read('AndroidManifest.xml'))
    manifest = next(attributes for tag, attributes in tags if tag == 'manifest')
    application = next(attributes for tag, attributes in tags if tag == 'application')
    sdk = next(attributes for tag, attributes in tags if tag == 'uses-sdk')
    permissions = [attributes.get('name') for tag, attributes in tags if tag.startswith('uses-permission')]
    if manifest.get('package') != 'ir.lifeguide.app':
        raise ValueError('APK application ID must be ir.lifeguide.app')
    if application.get('label') != 'لایف‌گاید':
        raise ValueError('APK must display the LifeGuide Persian product label')
    if application.get('allowBackup') is not False:
        raise ValueError('APK must explicitly disable Android app-data backup')
    if application.get('usesCleartextTraffic') is not False:
        raise ValueError('APK must explicitly disable cleartext network traffic')
    if bool(application.get('debuggable', False)) != (mode == 'debug'):
        raise ValueError('APK debuggable flag differs from the declared build mode')
    if 'android.permission.INTERNET' not in permissions:
        raise ValueError('APK lacks INTERNET permission')
    return {'result': 'PASS', 'mode': mode, 'package': manifest['package'],
            'versionName': manifest.get('versionName'), 'versionCode': manifest.get('versionCode'),
            'label': application['label'], 'debuggable': bool(application.get('debuggable', False)),
            'allowBackup': False, 'usesCleartextTraffic': False, 'internetPermission': True,
            'minSdkVersion': sdk.get('minSdkVersion'), 'targetSdkVersion': sdk.get('targetSdkVersion'),
            'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
            'limitations': 'Signature is checked separately by apksigner; device install/lifecycle UNVERIFIED.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--mode', choices=['debug', 'release'], required=True)
    options = parser.parse_args()
    print(json.dumps(check(options.apk, options.mode), ensure_ascii=False, indent=2))
