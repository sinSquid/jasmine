#!/usr/bin/env python3
"""Install the pinned Android release libraries without requiring Rust sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MAX_BYTES = 128 * 1024 * 1024
ABIS = {'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40), 'x86_64': (2, 62)}


def install(archive, manifest, root):
    archive = Path(archive)
    if archive.stat().st_size > MAX_BYTES:
        raise ValueError('Core archive is too large')
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != manifest['sha256']:
        raise ValueError('Core archive SHA-256 mismatch; no libraries installed')
    target = Path(root) / 'android/app/src/main/jniLibs'
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent, prefix='core-stage-') as temp:
        stage = Path(temp)
        with zipfile.ZipFile(archive) as bundle:
            for abi, (elf_class, machine) in ABIS.items():
                name = f'android/app/src/main/jniLibs/{abi}/librust.so'
                if bundle.namelist().count(name) != 1:
                    raise ValueError(f'Missing or duplicate core for {abi}')
                info = bundle.getinfo(name)
                if info.file_size > MAX_BYTES:
                    raise ValueError(f'Core for {abi} is too large')
                with bundle.open(info) as source:
                    header = source.read(20)
                    if (len(header) != 20 or header[:4] != b'\x7fELF'
                            or header[4] != elf_class or header[5] != 1
                            or struct.unpack_from('<H', header, 18)[0] != machine):
                        raise ValueError(f'Invalid ELF architecture for {abi}')
                    output = stage / abi / 'librust.so'
                    output.parent.mkdir()
                    with output.open('wb') as dest:
                        dest.write(header)
                        shutil.copyfileobj(source, dest)
        # Keep a complete previous tree until the staged tree has been installed.
        # Both renames are on the same filesystem; restore on a failed install.
        ready = stage / 'ready'
        if target.exists():
            shutil.copytree(target, ready)
        else:
            ready.mkdir()
        for abi in ABIS:
            (ready / abi).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(stage / abi / 'librust.so', ready / abi / 'librust.so')
        backup = target.with_name('jniLibs.previous')
        if backup.exists():
            raise RuntimeError(f'Previous recovery directory exists: {backup}; recover it before retrying')
        had_previous = target.exists()
        if had_previous:
            os.replace(target, backup)
        try:
            os.replace(ready, target)
        except OSError:
            if had_previous:
                # Keep the backup outside TemporaryDirectory if restoration fails.
                os.replace(backup, target)
            raise
        if had_previous:
            shutil.rmtree(backup)
    print(f"Installed Android core {manifest['version']} ({digest})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Use a previously downloaded archive')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'ci/android-core.json').read_text())
    if args.archive:
        install(args.archive, manifest, ROOT)
        return
    if not manifest['url'].startswith('https://github.com/'):
        raise ValueError('Expected an HTTPS GitHub release URL')
    with tempfile.TemporaryDirectory(prefix='jasmine-core-') as temp:
        archive = Path(temp) / 'core.zip'
        with urllib.request.urlopen(manifest['url'], timeout=30) as response, archive.open('wb') as dest:
            total = 0
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_BYTES:
                    raise ValueError('Core download is too large')
                dest.write(chunk)
        install(archive, manifest, ROOT)


if __name__ == '__main__':
    main()
