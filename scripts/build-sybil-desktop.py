#!/usr/bin/env python3
"""Build Sybil with bundled SimpleX on a Windows x64 or Apple Silicon host."""
import importlib.util
import json
import secrets
import tempfile
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
TARGET = {'Windows': 'windows', 'Darwin': 'macos'}.get(platform.system())
if TARGET is None:
    sys.exit('Use a Windows x64 or Apple Silicon build host.')
version = os.environ.get('SYBIL_RELEASE_VERSION', '1.0.0-beta.1')
build = os.environ.get('SYBIL_RELEASE_BUILD', '1')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?', version) or not build.isdigit():
    sys.exit('Invalid release identity')


def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def check_native_host(host, library):
    # A disposable encrypted database checks ABI/loading only; no relay is started.
    with tempfile.TemporaryDirectory(prefix='sybil-native-check-') as directory:
        payload = f'{directory}/profile-unicode-é\n{secrets.token_hex(32)}\n'
        result = subprocess.run([str(host), str(library)], input=payload.encode('utf-8'),
                                capture_output=True, timeout=30)
        if result.returncode or not result.stdout or json.loads(result.stdout.splitlines()[0]).get('type') != 'ok':
            raise RuntimeError(
                f'Bundled SimpleX initialization failed (exit {result.returncode}): '
                f'{result.stdout.decode("utf-8", errors="replace")[:2000]} '
                f'{result.stderr.decode("utf-8", errors="replace")[:2000]}'
            )


def flutter(*args):
    # Resolve the .bat launcher explicitly on Windows.
    executable = shutil.which('fvm.bat' if TARGET == 'windows' else 'fvm')
    if executable is None:
        raise RuntimeError('Install FVM before building')
    run(executable, 'flutter', *args)


spec = importlib.util.spec_from_file_location('fetch_desktop', ROOT / 'tools/simplex/fetch-desktop.py')
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)
native_target = 'windows-x86_64' if TARGET == 'windows' else 'macos-aarch64'
if TARGET == 'macos' and platform.machine() != 'arm64':
    sys.exit('The macOS packaging lane currently targets Apple Silicon.')
libs = fetcher.fetch(native_target, ROOT / 'build/simplex-desktop' / native_target)
host_build = ROOT / 'build/simplex-host'
run('cmake', '-S', 'tools/simplex', '-B', host_build, *(['-A', 'x64'] if TARGET == 'windows' else []))
run('cmake', '--build', host_build, '--config', 'Release')
if TARGET == 'windows':
    # Fail before the lengthy Flutter/Rust build if the native core cannot load.
    check_native_host(host_build / 'Release/simplex-host.exe', libs / 'libsimplex.dll')

defines = {
    'VIZOR_RELEASE_VERSION': version,
    'VIZOR_RELEASE_BUILD_NUMBER': build,
    'VIZOR_RELEASE_REPOSITORY': 'cpte-org/sybil-wallet',
    'VIZOR_UPDATE_CHECK_ENABLED': 'false',
    'VIZOR_DEEPLINK_BASE_URL': 'https://sybil.cash',
    'ZCASH_DEFAULT_NETWORK': 'main',
    'ZNS_BASE_SEPOLIA': 'false',
    'ZCASH_CONTACTS_EXPERIMENT': 'true',
    'SIGIL_NEAR_INTENTS_BASE_URL': 'https://api.sybil.cash/api/near-intents/1click',
    'SIGIL_NEAR_INTENTS_ALLOW_LOOPBACK': 'false',
    'VIZOR_FORM_FACTOR': 'desktop',
}
if TARGET == 'macos':
    overrides = ROOT / 'macos/Runner/Configs/FlavorOverrides.xcconfig'
    if overrides.exists():
        sys.exit('Remove existing macOS flavor overrides before this build.')
    overrides.write_text('PRODUCT_NAME = Sybil\nPRODUCT_BUNDLE_IDENTIFIER = cash.sybil.wallet\n')
    xcode_override = ROOT / 'build/sybil-unsigned.xcconfig'
    xcode_override.write_text('CODE_SIGNING_ALLOWED = NO\nCODE_SIGNING_REQUIRED = NO\nDEVELOPMENT_TEAM =\nARCHS = arm64\n')
    os.environ['XCODE_XCCONFIG_FILE'] = str(xcode_override)
try:
    flutter('build', TARGET, '--release', f'--build-name={version}', f'--build-number={build}',
            *(f'--dart-define={k}={v}' for k, v in defines.items()))
finally:
    if TARGET == 'macos':
        overrides.unlink(missing_ok=True)

out = ROOT / 'dist' / TARGET
out.mkdir(parents=True, exist_ok=True)
if TARGET == 'windows':
    bundle = ROOT / 'build/windows/x64/runner/Release'
    if not (bundle / 'Sybil.exe').exists():
        sys.exit('Missing Sybil.exe')
    shutil.copy2(host_build / 'Release/simplex-host.exe', bundle)
    shutil.copytree(libs, bundle / 'lib/simplex', dirs_exist_ok=True)
    shutil.copy2(ROOT / 'tools/simplex/licenses/OPENSSL-3.0.15-LICENSE.txt', bundle / 'lib/simplex')
    shutil.copy2(ROOT / 'tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt', bundle / 'lib/simplex')
    check_native_host(bundle / 'simplex-host.exe', bundle / 'lib/simplex/libsimplex.dll')
    shutil.make_archive(str(out / 'sybil-beta-mainnet-windows-x64'), 'zip', bundle)
else:
    app = ROOT / 'build/macos/Build/Products/Release/Sybil.app'
    if not app.exists():
        sys.exit('Missing Sybil.app')
    contents = app / 'Contents'
    shutil.copy2(host_build / 'simplex-host', contents / 'MacOS/simplex-host')
    bundled_libs = contents / 'Frameworks/simplex'
    shutil.copytree(libs, bundled_libs, dirs_exist_ok=True)
    shutil.copy2(ROOT / 'tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt', bundled_libs)
    # Keep dylib dependencies inside the relocated app, not upstream build paths.
    for library in bundled_libs.glob('*.dylib'):
        run('install_name_tool', '-id', f'@loader_path/{library.name}', library)
        dependencies = subprocess.check_output(['otool', '-L', str(library)], text=True).splitlines()[1:]
        for dependency in dependencies:
            old = dependency.strip().split(' (')[0]
            name = Path(old).name
            if (bundled_libs / name).exists() and old != f'@loader_path/{name}':
                run('install_name_tool', '-change', old, f'@loader_path/{name}', library)
    info_path = contents / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    for key in ('SUFeedURL', 'SUPublicEDKey'):
        info.pop(key, None)
    info['SUEnableAutomaticChecks'] = False
    info_path.write_bytes(plistlib.dumps(info))
    # Ad-hoc signing permits Apple Silicon execution; this is not notarization.
    for item in sorted(contents.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if item.suffix in ('.dylib', '.framework', '.xpc', '.app'):
            run('codesign', '--force', '--sign', '-', item)
    run('codesign', '--force', '--sign', '-', contents / 'MacOS/simplex-host')
    check_native_host(contents / 'MacOS/simplex-host', bundled_libs / 'libsimplex.dylib')
    helper_entitlements = ROOT / 'build/simplex-host.entitlements'
    helper_entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.app-sandbox': True,
        'com.apple.security.inherit': True,
    }))
    run('codesign', '--force', '--sign', '-', '--entitlements', helper_entitlements, contents / 'MacOS/simplex-host')
    entitlements = plistlib.loads((ROOT / 'macos/Runner/Release.entitlements').read_bytes())
    entitlements.pop('com.apple.application-identifier', None)
    entitlements.pop('com.apple.developer.team-identifier', None)
    app_entitlements = ROOT / 'build/sybil-app.entitlements'
    app_entitlements.write_bytes(plistlib.dumps(entitlements))
    run('codesign', '--force', '--sign', '-', '--entitlements', app_entitlements, app)
    run('codesign', '--verify', '--deep', '--strict', app)
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, out / 'sybil-beta-mainnet-macos-arm64.zip')
