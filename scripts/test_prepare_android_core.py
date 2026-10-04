import hashlib
import json
import os
from unittest.mock import patch
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from prepare_android_core import ABIS, install


class CorePreparationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'core.zip'

    def make_archive(self, invalid_abi=None):
        with zipfile.ZipFile(self.archive, 'w') as bundle:
            for abi, (elf_class, machine) in ABIS.items():
                header = bytearray(32)
                header[:6] = b'\x7fELF' + bytes([elf_class, 1])
                struct.pack_into('<H', header, 18, 0 if abi == invalid_abi else machine)
                bundle.writestr(f'android/app/src/main/jniLibs/{abi}/librust.so', header)
            bundle.writestr('../../outside', 'must not be extracted')
        return {'version': 'test', 'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest()}

    def test_installs_only_expected_elf_members(self):
        install(self.archive, self.make_archive(), self.root)
        self.assertEqual(len(list(self.root.rglob('*.so'))), 3)
        self.assertFalse((self.root / 'outside').exists())

    def test_checksum_mismatch_changes_nothing(self):
        manifest = self.make_archive()
        manifest['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            install(self.archive, manifest, self.root)
        self.assertEqual(list(self.root.rglob('*.so')), [])

    def test_architecture_failure_preserves_existing_libraries(self):
        manifest = self.make_archive(invalid_abi='x86_64')
        existing = self.root / 'android/app/src/main/jniLibs/arm64-v8a/librust.so'
        existing.parent.mkdir(parents=True)
        existing.write_bytes(b'previous library')
        with self.assertRaisesRegex(ValueError, 'architecture'):
            install(self.archive, manifest, self.root)
        self.assertEqual(existing.read_bytes(), b'previous library')

    def test_install_failure_restores_complete_previous_tree(self):
        manifest = self.make_archive()
        target = self.root / 'android/app/src/main/jniLibs'
        for abi in ABIS:
            dest = target / abi / 'librust.so'
            dest.parent.mkdir(parents=True)
            dest.write_bytes(('old-' + abi).encode())
        original_replace = os.replace
        def fail_install(source, destination):
            if Path(source).name == 'ready':
                raise OSError('injected install failure')
            return original_replace(source, destination)
        with patch('prepare_android_core.os.replace', side_effect=fail_install):
            with self.assertRaisesRegex(OSError, 'injected'):
                install(self.archive, manifest, self.root)
        for abi in ABIS:
            self.assertEqual((target / abi / 'librust.so').read_bytes(), ('old-' + abi).encode())
        self.assertFalse(target.with_name('jniLibs.previous').exists())

    def test_manifest_pins_release_and_checksum(self):
        manifest = json.loads((Path(__file__).resolve().parent.parent / 'ci/android-core.json').read_text())
        self.assertIn('/' + manifest['version'] + '/', manifest['url'])
        self.assertRegex(manifest['sha256'], r'^[0-9a-f]{64}$')


if __name__ == '__main__':
    unittest.main()
