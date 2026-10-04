#!/usr/bin/env python3
"""Manually check the pinned arm64 download setter in isolated Android processes.

Usage: python3 scripts/check_android_download_restart.py --serial DEVICE_SERIAL
Requires an Android SDK, NDK and JDK. Does not start or access the installed app.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid
import zipfile

from patch_android_core import load_patch_manifest, patch_library

ROOT = Path(__file__).resolve().parent.parent
SOURCES = Path(__file__).resolve().parent / 'android_download_restart_probe'
CORE_VERSION = 'v1.7.21'
SOURCE_SHA256 = 'ab5e0a521384b72b88bdede85121a879ec72be01d298da1d2f9417e19ddc46ee'
FLAG_VA = 0xf6dd60
INITIALIZED_VA = 0xf6dd68
FIX_VA = 0x67e894
FIX_BYTES = '28008052'
RESULT_PREFIX = 'JASMINE_RESTART_RESULT '


def run(command, label, timeout=60, env=None):
    """Never echo native stdout/stderr, which may contain response payloads."""
    try:
        result = subprocess.run(
            [str(value) for value in command], capture_output=True, text=True,
            timeout=timeout, env=env, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f'{label} timed out after {timeout}s') from error
    if result.returncode:
        raise RuntimeError(f'{label} failed (exit {result.returncode}); output suppressed')
    return result.stdout


def version_key(path):
    return tuple(int(part) for part in re.findall(r'\d+', path.name))


def discover_sdk():
    candidates = [os.environ.get('ANDROID_SDK_ROOT'), os.environ.get('ANDROID_HOME')]
    properties = ROOT / 'android/local.properties'
    if properties.is_file():
        for line in properties.read_text().splitlines():
            if line.startswith('sdk.dir='):
                candidates.append(line.partition('=')[2].replace('\\:', ':').replace('\\\\', '\\'))
    candidates.extend((Path.home() / 'Library/Android/sdk', Path.home() / 'Android/Sdk'))
    for candidate in candidates:
        if candidate:
            path = Path(candidate).expanduser().resolve()
            if (path / 'platform-tools/adb').is_file():
                return path
    raise RuntimeError('Android SDK not found; set ANDROID_SDK_ROOT')


def discover_java():
    candidates = [os.environ.get('JAVA_HOME')]
    if platform.system() == 'Darwin':
        candidates.append('/Applications/Android Studio.app/Contents/jbr/Contents/Home')
        if Path('/usr/libexec/java_home').is_file():
            try:
                candidates.append(run(['/usr/libexec/java_home'], 'JDK discovery', 10).strip())
            except RuntimeError:
                pass  # Other explicit and PATH candidates can still provide the JDK.
    javac = shutil.which('javac')
    if javac:
        candidates.append(Path(javac).resolve().parent.parent)
    for candidate in candidates:
        if candidate:
            path = Path(candidate).expanduser().resolve()
            if (path / 'bin/javac').is_file() and (path / 'bin/java').is_file():
                return path
    raise RuntimeError('JDK not found; set JAVA_HOME')


def discover_tools(sdk):
    build_tools = sorted((sdk / 'build-tools').glob('*'), key=version_key, reverse=True)
    d8 = next((path / 'd8' for path in build_tools if (path / 'd8').is_file()), None)
    platforms = sorted((sdk / 'platforms').glob('android-*'), key=version_key, reverse=True)
    android_jar = next((path / 'android.jar' for path in platforms
                        if (path / 'android.jar').is_file()), None)
    ndks = []
    for name in ('ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT'):
        if os.environ.get(name):
            ndks.append(Path(os.environ[name]).expanduser())
    ndks.extend(sorted((sdk / 'ndk').glob('*'), key=version_key, reverse=True))
    host = {'Darwin': 'darwin', 'Linux': 'linux'}.get(platform.system())
    clang = None
    if host:
        for ndk in ndks:
            compilers = sorted((ndk / 'toolchains/llvm/prebuilt').glob(
                f'{host}-*/bin/aarch64-linux-android23-clang'))
            if compilers:
                # Keep the target/API wrapper name even when it is a symlink.
                clang = compilers[0].absolute()
                break
    if not d8 or not android_jar or not clang:
        raise RuntimeError('Install SDK build-tools, an Android platform and a compatible NDK')
    return d8, android_jar, clang


def checked_library():
    core = json.loads((ROOT / 'ci/android-core.json').read_text())
    manifest = load_patch_manifest(core, ROOT)
    if manifest is None or manifest['core_version'] != CORE_VERSION:
        raise RuntimeError('The read-only flag probe only supports pinned core v1.7.21')
    spec = manifest['abis']['arm64-v8a']
    if (spec['source_sha256'] != SOURCE_SHA256
            or not any(p['va'] == FIX_VA and p['after_hex'] == FIX_BYTES
                       for p in spec['patches'])):
        raise RuntimeError('The manifest must include the verified arm64 restart-flag fix')
    library = ROOT / 'android/app/src/main/jniLibs/arm64-v8a/librust.so'
    data = library.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != spec['patched_sha256']:
        raise RuntimeError('Installed arm64 core does not match the patched manifest SHA-256')
    patch_library(data, spec)  # Includes architecture, instruction and PT_LOAD checks.
    table = struct.unpack_from('<Q', data, 32)[0]
    entry_size, count = struct.unpack_from('<HH', data, 54)
    for va in (FLAG_VA, INITIALIZED_VA):
        matches = []
        for index in range(count):
            kind, flags, _, address, _, _, memory_size, _ = struct.unpack_from(
                '<IIQQQQQQ', data, table + index * entry_size)
            if kind == 1 and flags & 4 and address <= va < address + memory_size:
                matches.append(address)
        if len(matches) != 1:
            raise RuntimeError('Read-only flag address is outside a unique readable PT_LOAD')
    return data, digest


def build_probe(work, sdk):
    d8, android_jar, clang = discover_tools(sdk)
    java = discover_java()
    env = os.environ.copy()
    env['JAVA_HOME'] = str(java)
    env['PATH'] = str(java / 'bin') + os.pathsep + env.get('PATH', '')
    classes, dex = work / 'classes', work / 'dex'
    classes.mkdir()
    dex.mkdir()
    run([java / 'bin/javac', '--release', '8', '-classpath', android_jar,
         '-d', classes, SOURCES / 'DownloadProbe.java',
         SOURCES / 'opensource/jenny/Jni.java'], 'Probe Java compilation', env=env)
    run([d8, '--min-api', '23', '--lib', android_jar, '--output', dex,
         *sorted(classes.rglob('*.class'))], 'Probe DEX compilation', env=env)
    jar = work / 'probe.jar'
    with zipfile.ZipFile(jar, 'w') as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    helper = work / 'libprobe.so'
    run([clang, '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
         f'-DRESTART_FLAG_VA={FLAG_VA}', f'-DRESTART_INITIALIZED_VA={INITIALIZED_VA}',
         SOURCES / 'probe.c', '-ldl', '-o', helper], 'Read-only helper compilation')
    return jar, helper


def result_from_output(output, requested):
    lines = [line[len(RESULT_PREFIX):] for line in output.splitlines()
             if line.startswith(RESULT_PREFIX)]
    if len(lines) != 1:
        raise RuntimeError('Probe did not return exactly one structured result')
    value = json.loads(lines[0])
    expected = {'requested': requested, 'loaded': requested, 'flag_after': 1,
                'membership_false': True}
    if (not isinstance(value, dict) or any(type(value.get(key)) is not type(wanted)
            or value[key] != wanted for key, wanted in expected.items())
            or type(value.get('flag_before')) is not int or value['flag_before'] not in (-3, 0)):
        raise RuntimeError(f'Isolated probe assertions failed for thread count {requested}')
    return {key: value[key] for key in (*expected, 'flag_before')}


def cleanup(adb, serial, remote):
    # The unique work directory also occurs as an exact app_process argument.
    # Check it before killing a recorded PID, so PID reuse cannot target the app.
    quoted = shlex.quote(remote)
    command = (
        f'dir={quoted}; '
        'if [ -f "$dir/probe.pid" ]; then read -r pid < "$dir/probe.pid"; '
        'case "$pid" in ""|*[!0-9]*) ;; *) '
        'if [ -r "/proc/$pid/cmdline" ] && '
        'tr "\\000" "\\n" < "/proc/$pid/cmdline" | grep -F -x -q "$dir"; '
        'then kill -9 "$pid" 2>/dev/null || true; fi ;; esac; fi; '
        'rm -rf -- "$dir"')
    run([adb, '-s', serial, 'shell', command], 'Device temporary-directory cleanup', 15)


def check(serial, probe_timeout):
    data, digest = checked_library()
    sdk = discover_sdk()
    adb = sdk / 'platform-tools/adb'
    if run([adb, '-s', serial, 'get-state'], 'Device connection', 15).strip() != 'device':
        raise RuntimeError('The selected Android device is not ready')
    abis = run([adb, '-s', serial, 'shell', 'getprop ro.product.cpu.abilist'],
               'Device architecture', 15).strip().split(',')
    if 'arm64-v8a' not in abis:
        raise RuntimeError('This probe requires an arm64 Android device')
    api = run([adb, '-s', serial, 'shell', 'getprop ro.build.version.sdk'],
              'Device API level', 15).strip()
    if not api.isdecimal() or int(api) < 23:
        raise RuntimeError('This probe requires Android API 23 or newer')
    remote = '/data/local/tmp/jasmine-download-restart-' + uuid.uuid4().hex
    results = []
    with tempfile.TemporaryDirectory(prefix='jasmine-download-restart-') as temporary:
        work = Path(temporary)
        jar, helper = build_probe(work, sdk)
        library = work / 'librust.so'
        library.write_bytes(data)  # Test the already-verified immutable local snapshot.
        remote_attempted = False
        try:
            remote_attempted = True
            run([adb, '-s', serial, 'shell', shlex.join(['mkdir', '-m', '700', remote])],
                'Device temporary-directory creation', 15)
            run([adb, '-s', serial, 'push', library, helper, jar, remote + '/'],
                'Probe upload', 90)
            device_digest = run([adb, '-s', serial, 'shell',
                                 shlex.join(['sha256sum', remote + '/librust.so'])],
                                'Uploaded core verification', 15).split()
            if not device_digest or device_digest[0] != digest:
                raise RuntimeError('Uploaded core SHA-256 mismatch')
            for count in (1, 2, 5):
                process = ['env', 'CLASSPATH=' + remote + '/probe.jar',
                           '/system/bin/app_process64', remote, 'DownloadProbe',
                           remote + '/librust.so', remote + f'/state-{count}',
                           remote + '/libprobe.so', str(count)]
                wrapper = f'echo $$ > {shlex.quote(remote + "/probe.pid")}; exec ' + shlex.join(process)
                command = shlex.join(['timeout', '-s', 'KILL', str(probe_timeout),
                                      'sh', '-c', wrapper])
                output = run([adb, '-s', serial, 'shell', command],
                             f'Isolated thread-count {count} probe', probe_timeout + 15)
                result = result_from_output(output, count)
                results.append(result)
                print(json.dumps(result, sort_keys=True), flush=True)
        finally:
            if remote_attempted:
                pending_error = sys.exc_info()[1]
                try:
                    cleanup(adb, serial, remote)
                except (OSError, RuntimeError) as error:
                    if pending_error is None:
                        raise
                    print(f'Cleanup also failed for {remote}: {error}', file=sys.stderr)
    return {'core_version': CORE_VERSION, 'library_sha256': digest,
            'passed': True, 'cases': results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, help='Explicit adb device serial')
    parser.add_argument('--timeout', type=int, default=45,
                        help='Per-process device timeout in seconds (5–120; default 45)')
    args = parser.parse_args(argv)
    if not args.serial.strip() or not 5 <= args.timeout <= 120:
        parser.error('--serial must be nonempty and --timeout must be between 5 and 120')
    try:
        print(json.dumps(check(args.serial, args.timeout), sort_keys=True))
    except (OSError, ValueError, RuntimeError) as error:
        print(f'Download restart check failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
