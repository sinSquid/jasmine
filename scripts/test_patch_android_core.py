import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from patch_android_core import ABIS, check_libraries, load_patch_manifest, main, patch_library


def make_library(elf_class, machine):
    """Synthetic ELF with separate read-only and executable mappings, never executed."""
    data = bytearray(0x300)
    data[:7] = b'\x7fELF' + bytes([elf_class, 1, 1])
    struct.pack_into('<HHI', data, 16, 3, machine, 1)
    header, program = (52, 32) if elf_class == 1 else (64, 56)
    if elf_class == 1:
        struct.pack_into('<I', data, 28, header)
        struct.pack_into('<HHH', data, 40, header, program, 2)
        struct.pack_into('<IIIIIIII', data, header, 1, 0, 0x1000, 0, 0x100, 0x100, 4, 0x100)
        struct.pack_into('<IIIIIIII', data, header + program, 1, 0x100, 0x4000, 0, 0x180, 0x180, 5, 0x100)
    else:
        struct.pack_into('<Q', data, 32, header)
        struct.pack_into('<HHH', data, 52, header, program, 2)
        struct.pack_into('<IIQQQQQQ', data, header, 1, 4, 0, 0x1000, 0, 0x100, 0x100, 0x100)
        struct.pack_into('<IIQQQQQQ', data, header + program, 1, 5, 0x100, 0x4000, 0, 0x180, 0x180, 0x100)
    entries = [
        {'name': 'first', 'va': 0x4020, 'file_offset': 0x120,
         'before_hex': '11223344', 'after_hex': '55667788'},
        {'name': 'second', 'va': 0x4030, 'file_offset': 0x130,
         'before_hex': '01020304', 'after_hex': '05060708'},
    ]
    for entry in entries:
        offset = entry['file_offset']
        data[offset:offset + 4] = bytes.fromhex(entry['before_hex'])
    original = bytes(data)
    for entry in entries:
        offset = entry['file_offset']
        data[offset:offset + 4] = bytes.fromhex(entry['after_hex'])
    result = bytes(data)
    spec = {'elf_class': elf_class, 'machine': machine,
            'source_sha256': hashlib.sha256(original).hexdigest(),
            'patched_sha256': hashlib.sha256(result).hexdigest(), 'patches': entries}
    return original, result, spec


class LibraryPatchTest(unittest.TestCase):
    def setUp(self):
        self.data, self.expected, self.spec = make_library(2, 183)

    def test_exact_source_patches_all_architectures_and_is_idempotent(self):
        for abi, architecture in ABIS.items():
            with self.subTest(abi=abi):
                source, expected, spec = make_library(*architecture)
                original = bytearray(source)
                self.assertEqual(patch_library(original, spec), expected)
                self.assertEqual(original, source)
                self.assertEqual(patch_library(expected, spec), expected)
                self.assertEqual(len(source), len(expected))

    def test_unknown_version_and_partially_patched_library_are_rejected(self):
        unknown = bytearray(self.data)
        unknown[-1] = 1
        mixed = bytearray(self.data)
        mixed[0x120:0x124] = self.expected[0x120:0x124]
        for data in (unknown, mixed):
            with self.subTest(data=data[0x120:0x124]), self.assertRaisesRegex(ValueError, 'Unknown core SHA-256'):
                patch_library(data, self.spec)

    def test_expected_source_instructions_must_match(self):
        self.spec['patches'][0]['before_hex'] = '00000000'
        with self.assertRaisesRegex(ValueError, 'expected instruction bytes'):
            patch_library(self.data, self.spec)

    def test_already_patched_input_still_validates_manifest_instructions(self):
        self.spec['patches'][0]['after_hex'] = '00000000'
        with self.assertRaisesRegex(ValueError, 'expected instruction bytes'):
            patch_library(self.expected, self.spec)

    def test_final_checksum_is_verified(self):
        self.spec['patched_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Patched core SHA-256 mismatch'):
            patch_library(self.data, self.spec)

    def test_invalid_instruction_specifications_are_rejected(self):
        cases = [('before_hex', ''), ('before_hex', 'xx'), ('before_hex', '123'),
                 ('after_hex', '00'), ('after_hex', '11223344'),
                 ('va', -1), ('va', True), ('va', '0x4020'),
                 ('file_offset', -1), ('file_offset', None), ('name', '')]
        for key, value in cases:
            spec = copy.deepcopy(self.spec)
            spec['patches'][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                patch_library(self.data, spec)
        for key, value in [('patches', []), ('patches', [None]), ('source_sha256', 'invalid'),
                           ('patched_sha256', self.spec['source_sha256']), ('machine', 0)]:
            spec = copy.deepcopy(self.spec)
            spec[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                patch_library(self.data, spec)

    def test_overlapping_va_or_file_ranges_are_rejected(self):
        for key in ('va', 'file_offset'):
            spec = copy.deepcopy(self.spec)
            spec['patches'][1][key] = spec['patches'][0][key] + 2
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'Overlapping'):
                patch_library(self.data, spec)

    def test_only_matching_file_backed_executable_addresses_are_accepted(self):
        for va, offset in [(0x4020, 0x121), (0x1020, 0x20), (0x417e, 0x27e),
                           (0x4200, 0x300), (0x5000, 0x120)]:
            spec = copy.deepcopy(self.spec)
            spec['patches'][0].update(va=va, file_offset=offset)
            with self.subTest(va=va, offset=offset), self.assertRaisesRegex(ValueError, 'PT_LOAD mapping'):
                patch_library(self.data, spec)

    def test_invalid_elf_headers_and_segments_are_rejected_even_with_known_hash(self):
        # Mutate fixture metadata and re-pin only its source hash to reach ELF checks.
        variants = []
        for offset, value in [(0, 0), (4, 1), (5, 2), (6, 0), (18, 0)]:
            data = bytearray(self.data)
            data[offset] = value
            variants.append(data)
        variants.append(self.data[:20])
        for fmt, offset, value in [('<Q', 32, 0xffff), ('<H', 54, 1), ('<H', 56, 0),
                                    ('<H', 56, 0xffff), ('<I', 124, 4),
                                    ('<Q', 152, 0x400), ('<Q', 160, 1)]:
            data = bytearray(self.data)
            struct.pack_into(fmt, data, offset, value)
            variants.append(data)
        for index, data in enumerate(variants):
            spec = copy.deepcopy(self.spec)
            spec['source_sha256'] = hashlib.sha256(data).hexdigest()
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, 'ELF'):
                patch_library(data, spec)

    def test_ambiguous_executable_mapping_is_rejected(self):
        data = bytearray(self.data)
        data[64:120] = data[120:176]
        self.spec['source_sha256'] = hashlib.sha256(data).hexdigest()
        with self.assertRaisesRegex(ValueError, 'unique executable PT_LOAD mapping'):
            patch_library(data, self.spec)


class PatchManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.core = {'version': 'fixture-v1', 'local_patch_manifest': 'ci/local-patches.json'}
        self.manifest = {'schema_version': 1, 'core_version': 'fixture-v1', 'abis': {}}
        for abi, architecture in ABIS.items():
            _, result, spec = make_library(*architecture)
            self.manifest['abis'][abi] = spec
            dest = self.root / 'android/app/src/main/jniLibs' / abi / 'librust.so'
            dest.parent.mkdir(parents=True)
            dest.write_bytes(result)
        (self.root / 'ci').mkdir()
        self.write_manifest()

    def write_manifest(self):
        (self.root / self.core['local_patch_manifest']).write_text(json.dumps(self.manifest))
        (self.root / 'ci/android-core.json').write_text(json.dumps(self.core))

    def test_optional_manifest_preserves_legacy_behavior(self):
        self.assertIsNone(load_patch_manifest({'version': 'legacy'}, self.root))

    def test_pinned_manifest_and_read_only_cli_check(self):
        loaded = load_patch_manifest(self.core, self.root)
        self.assertEqual(loaded, self.manifest)
        before = {path: path.read_bytes() for path in self.root.rglob('*.so')}
        check_libraries(self.root, loaded)
        with patch('patch_android_core.ROOT', self.root):
            main(['--check'])
        self.assertEqual({path: path.read_bytes() for path in before}, before)

    def test_check_rejects_unpatched_library_without_mutating_any_files(self):
        path = self.root / 'android/app/src/main/jniLibs/arm64-v8a/librust.so'
        original, _, _ = make_library(*ABIS['arm64-v8a'])
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, 'patched SHA-256'):
            check_libraries(self.root, self.manifest)
        self.assertEqual(path.read_bytes(), original)

    def test_unknown_missing_or_mislabeled_abi_is_rejected(self):
        for mutation in ('unknown', 'missing', 'architecture'):
            saved = copy.deepcopy(self.manifest)
            if mutation == 'unknown':
                self.manifest['abis']['mips'] = self.manifest['abis']['arm64-v8a']
            elif mutation == 'missing':
                del self.manifest['abis']['x86_64']
            else:
                self.manifest['abis']['x86_64'] = self.manifest['abis']['arm64-v8a']
            self.write_manifest()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                load_patch_manifest(self.core, self.root)
            self.manifest = saved

    def test_version_and_schema_must_match(self):
        for key, value in [('core_version', 'fixture-v2'), ('schema_version', 2), ('schema_version', True)]:
            saved = copy.deepcopy(self.manifest)
            self.manifest[key] = value
            self.write_manifest()
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, 'version'):
                load_patch_manifest(self.core, self.root)
            self.manifest = saved

    def test_manifest_path_cannot_escape_repository(self):
        for value in ('../outside.json', str(self.root / 'ci/local-patches.json'), '', None):
            self.core['local_patch_manifest'] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'path|repository'):
                load_patch_manifest(self.core, self.root)

    def test_check_requires_configured_manifest(self):
        (self.root / 'ci/android-core.json').write_text(json.dumps({'version': 'legacy'}))
        with patch('patch_android_core.ROOT', self.root), self.assertRaisesRegex(ValueError, 'No local_patch_manifest'):
            main(['--check'])


if __name__ == '__main__':
    unittest.main()
