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
from test_patch_android_core import make_library


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

    def make_patched_archive(self):
        patches = {'schema_version': 1, 'core_version': 'fixture-v1', 'abis': {}}
        expected = {}
        with zipfile.ZipFile(self.archive, 'w') as bundle:
            for abi, architecture in ABIS.items():
                source, expected[abi], patches['abis'][abi] = make_library(*architecture)
                bundle.writestr(f'android/app/src/main/jniLibs/{abi}/librust.so', source)
        manifest = {'version': 'fixture-v1', 'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                    'local_patch_manifest': 'ci/local-patches.json'}
        (self.root / 'ci').mkdir()
        path = self.root / manifest['local_patch_manifest']
        path.write_text(json.dumps(patches))
        return manifest, patches, path, expected

    def make_previous_tree(self):
        target = self.root / 'android/app/src/main/jniLibs'
        for abi in ABIS:
            dest = target / abi / 'librust.so'
            dest.parent.mkdir(parents=True)
            dest.write_bytes(('old-' + abi).encode())
        (target / 'keep.txt').write_bytes(b'unrelated library metadata')
        return target

    def snapshot(self, target):
        return {str(path.relative_to(target)): path.read_bytes()
                for path in target.rglob('*') if path.is_file()}

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

    def test_installs_all_patched_abis_and_preserves_unrelated_files(self):
        manifest, _, _, expected = self.make_patched_archive()
        target = self.make_previous_tree()
        install(self.archive, manifest, self.root)
        for abi in ABIS:
            self.assertEqual((target / abi / 'librust.so').read_bytes(), expected[abi])
        self.assertEqual((target / 'keep.txt').read_bytes(), b'unrelated library metadata')
        self.assertFalse(target.with_name('jniLibs.previous').exists())

    def test_last_abi_patch_failure_leaves_complete_previous_tree_unchanged(self):
        manifest, patches, path, _ = self.make_patched_archive()
        target = self.make_previous_tree()
        before = self.snapshot(target)
        patches['abis']['x86_64']['patches'][0]['before_hex'] = '00000000'
        path.write_text(json.dumps(patches))
        with self.assertRaisesRegex(ValueError, 'x86_64: first: expected instruction bytes'):
            install(self.archive, manifest, self.root)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual(list(target.parent.glob('core-stage-*')), [])
        self.assertFalse(target.with_name('jniLibs.previous').exists())

    def test_patch_failure_without_previous_tree_installs_nothing(self):
        manifest, patches, path, _ = self.make_patched_archive()
        patches['abis']['x86_64']['patched_sha256'] = '0' * 64
        path.write_text(json.dumps(patches))
        with self.assertRaisesRegex(ValueError, 'x86_64: Patched core SHA-256 mismatch'):
            install(self.archive, manifest, self.root)
        target = self.root / 'android/app/src/main/jniLibs'
        self.assertFalse(target.exists())
        self.assertEqual(list(target.parent.glob('core-stage-*')), [])

    def test_manifest_version_failure_preserves_previous_tree(self):
        manifest, patches, path, _ = self.make_patched_archive()
        target = self.make_previous_tree()
        before = self.snapshot(target)
        patches['core_version'] = 'another-release'
        path.write_text(json.dumps(patches))
        with self.assertRaisesRegex(ValueError, 'version mismatch'):
            install(self.archive, manifest, self.root)
        self.assertEqual(self.snapshot(target), before)

    def test_patched_install_rename_failure_restores_previous_tree(self):
        manifest, _, _, _ = self.make_patched_archive()
        target = self.make_previous_tree()
        before = self.snapshot(target)
        original_replace = os.replace

        def fail_install(source, destination):
            if Path(source).name == 'ready':
                raise OSError('injected patched install failure')
            return original_replace(source, destination)

        with patch('prepare_android_core.os.replace', side_effect=fail_install):
            with self.assertRaisesRegex(OSError, 'injected patched install'):
                install(self.archive, manifest, self.root)
        self.assertEqual(self.snapshot(target), before)
        self.assertFalse(target.with_name('jniLibs.previous').exists())

    def test_failed_restore_preserves_backup_outside_temporary_stage(self):
        manifest, _, _, _ = self.make_patched_archive()
        target = self.make_previous_tree()
        before = self.snapshot(target)
        original_replace = os.replace

        def fail_install_and_restore(source, destination):
            if Path(source).name in ('ready', 'jniLibs.previous'):
                raise OSError('injected install and restore failure')
            return original_replace(source, destination)

        with patch('prepare_android_core.os.replace', side_effect=fail_install_and_restore):
            with self.assertRaisesRegex(OSError, 'restore failure'):
                install(self.archive, manifest, self.root)
        self.assertFalse(target.exists())
        self.assertEqual(self.snapshot(target.with_name('jniLibs.previous')), before)
        self.assertEqual(list(target.parent.glob('core-stage-*')), [])

    def test_existing_recovery_backup_blocks_install_without_changing_either_tree(self):
        manifest, _, _, _ = self.make_patched_archive()
        target = self.make_previous_tree()
        before = self.snapshot(target)
        backup = target.with_name('jniLibs.previous')
        backup.mkdir()
        (backup / 'recover').write_bytes(b'previous interrupted install')
        with self.assertRaisesRegex(RuntimeError, 'recovery directory exists'):
            install(self.archive, manifest, self.root)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual((backup / 'recover').read_bytes(), b'previous interrupted install')


if __name__ == '__main__':
    unittest.main()
