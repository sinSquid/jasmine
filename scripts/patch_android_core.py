#!/usr/bin/env python3
"""Check the pinned local Android core patches; installation uses prepare_android_core.py."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parent.parent
ABIS = {'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40), 'x86_64': (2, 62)}


def _integer(value, label):
    if type(value) is not int or value < 0:
        raise ValueError(f'{label} must be a non-negative integer')
    return value


def _patches(spec):
    if not isinstance(spec, dict):
        raise ValueError('Invalid ABI patch specification')
    architecture = (spec.get('elf_class'), spec.get('machine'))
    if any(type(value) is not int for value in architecture) or architecture not in ABIS.values():
        raise ValueError('Unsupported ELF architecture in patch specification')
    for key in ('source_sha256', 'patched_sha256'):
        if not isinstance(spec.get(key), str) or not re.fullmatch(r'[0-9a-f]{64}', spec[key]):
            raise ValueError(f'Invalid {key}')
    if spec['source_sha256'] == spec['patched_sha256']:
        raise ValueError('Source and patched SHA-256 must differ')
    entries = spec.get('patches')
    if not isinstance(entries, list) or not entries:
        raise ValueError('Patch list must not be empty')
    result = []
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get('name'), str) or not entry['name']:
            raise ValueError('Every patch needs a name')
        name = entry['name']
        va = _integer(entry.get('va'), f'{name} VA')
        offset = _integer(entry.get('file_offset'), f'{name} file offset')
        instructions = []
        for key in ('before_hex', 'after_hex'):
            value = entry.get(key)
            if not isinstance(value, str) or not re.fullmatch(r'(?:[0-9a-fA-F]{2})+', value):
                raise ValueError(f'{name}: {key} must contain non-empty instruction bytes')
            instructions.append(bytes.fromhex(value))
        before, after = instructions
        if len(before) != len(after):
            raise ValueError(f'{name}: patch must preserve instruction length')
        if before == after:
            raise ValueError(f'{name}: patch does not change any bytes')
        result.append((name, va, offset, before, after))
    for index, label in ((1, 'VA'), (2, 'file offset')):
        previous_end = -1
        for item in sorted(result, key=lambda item: item[index]):
            if item[index] < previous_end:
                raise ValueError(f'Overlapping patch {label} ranges')
            previous_end = item[index] + len(item[3])
    return result


def _executable_segments(data, spec):
    elf_class = spec['elf_class']
    header_size, program_size = (52, 32) if elf_class == 1 else (64, 56)
    if (len(data) < header_size or data[:4] != b'\x7fELF'
            or data[4:7] != bytes([elf_class, 1, 1])
            or struct.unpack_from('<H', data, 18)[0] != spec['machine']):
        raise ValueError('Invalid ELF architecture or header')
    if elf_class == 1:
        table = struct.unpack_from('<I', data, 28)[0]
        entry_size, count = struct.unpack_from('<HH', data, 42)
    else:
        table = struct.unpack_from('<Q', data, 32)[0]
        entry_size, count = struct.unpack_from('<HH', data, 54)
    if (not count or count == 0xffff or table < header_size
            or entry_size < program_size or table + entry_size * count > len(data)):
        raise ValueError('Invalid ELF program header table')
    segments = []
    for index in range(count):
        start = table + index * entry_size
        if elf_class == 1:
            kind, offset, va, _, size, memory_size, flags, _ = struct.unpack_from('<IIIIIIII', data, start)
        else:
            kind, flags, offset, va, _, size, memory_size, _ = struct.unpack_from('<IIQQQQQQ', data, start)
        if kind != 1:  # PT_LOAD
            continue
        if (size > memory_size or offset + size > len(data)
                or va + memory_size > 1 << (32 if elf_class == 1 else 64)):
            raise ValueError('Invalid ELF PT_LOAD bounds')
        if flags & 1:  # PF_X: patches must be inside file-backed executable code.
            segments.append((va, offset, size))
    if not segments:
        raise ValueError('ELF has no executable PT_LOAD segment')
    return segments


def patch_library(data, spec):
    """Return exactly the pinned patched ELF, or reject an unknown/mixed input."""
    patches = _patches(spec)
    digest = hashlib.sha256(data).hexdigest()
    if digest not in (spec['source_sha256'], spec['patched_sha256']):
        raise ValueError('Unknown core SHA-256; expected the pinned source or patched library')
    segments = _executable_segments(data, spec)
    is_patched = digest == spec['patched_sha256']
    for name, va, offset, before, after in patches:
        mappings = [segment_offset + va - segment_va
                    for segment_va, segment_offset, size in segments
                    if segment_va <= va and va + len(before) <= segment_va + size]
        if len(mappings) != 1 or mappings[0] != offset:
            raise ValueError(f'{name}: VA/file offset is not a unique executable PT_LOAD mapping')
        expected = after if is_patched else before
        if data[offset:offset + len(expected)] != expected:
            raise ValueError(f'{name}: expected instruction bytes do not match')
    if is_patched:
        return bytes(data)
    patched = bytearray(data)
    for _, _, offset, before, after in patches:
        patched[offset:offset + len(before)] = after
    result = bytes(patched)
    if hashlib.sha256(result).hexdigest() != spec['patched_sha256']:
        raise ValueError('Patched core SHA-256 mismatch')
    return result


def load_patch_manifest(core_manifest, root):
    """Load the optional repository-relative patch manifest for this core release."""
    if 'local_patch_manifest' not in core_manifest:
        return None
    relative = core_manifest['local_patch_manifest']
    if not isinstance(relative, str) or not relative:
        raise ValueError('Invalid local_patch_manifest path')
    root = Path(root).resolve()
    path = (root / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(root):
        raise ValueError('local_patch_manifest must stay inside the repository')
    manifest = json.loads(path.read_text())
    if not isinstance(manifest, dict) or type(manifest.get('schema_version')) is not int or manifest['schema_version'] != 1:
        raise ValueError('Unsupported local patch manifest schema_version')
    if not core_manifest.get('version') or manifest.get('core_version') != core_manifest['version']:
        raise ValueError('Local patch manifest core version mismatch')
    specs = manifest.get('abis')
    if not isinstance(specs, dict) or set(specs) != set(ABIS):
        raise ValueError('Local patch manifest must specify exactly the supported ABIs')
    for abi, architecture in ABIS.items():
        spec = specs[abi]
        _patches(spec)
        if (spec['elf_class'], spec['machine']) != architecture:
            raise ValueError(f'Invalid patch architecture for {abi}')
    return manifest


def check_libraries(root, manifest):
    """Read-only check: all installed ABIs must already be the pinned patched ELF."""
    target = Path(root) / 'android/app/src/main/jniLibs'
    for abi in ABIS:
        spec = manifest['abis'][abi]
        data = (target / abi / 'librust.so').read_bytes()
        if hashlib.sha256(data).hexdigest() != spec['patched_sha256']:
            raise ValueError(f'{abi}: installed core does not match the patched SHA-256')
        patch_library(data, spec)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', required=True,
                        help='Verify installed libraries without changing any files')
    parser.parse_args(argv)
    core = json.loads((ROOT / 'ci/android-core.json').read_text())
    manifest = load_patch_manifest(core, ROOT)
    if manifest is None:
        raise ValueError('No local_patch_manifest is configured')
    check_libraries(ROOT, manifest)
    print(f"Verified patched Android core {manifest['core_version']} ({len(ABIS)} ABIs)")


if __name__ == '__main__':
    main()
