#!/usr/bin/env python3
"""Validate built OwnGoal CLI packages. This does not replace device tests."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

VROOT_PACKAGES = {'wiki.qaq.fish', 'wiki.qaq.uutils'}
ENTITLEMENTS = [
    'platform-application',
    'com.apple.private.security.no-sandbox',
    'com.apple.private.security.storage.AppBundles',
    'com.apple.private.security.storage.AppDataContainers',
]


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def audit(deb):
    package = run('dpkg-deb', '-f', str(deb), 'Package')
    architecture = run('dpkg-deb', '-f', str(deb), 'Architecture')
    require(architecture in {'iphoneos-arm64', 'iphoneos-arm64e'}, 'unknown layout')
    roothide = architecture == 'iphoneos-arm64e'
    with tempfile.TemporaryDirectory(prefix='binpack-audit-') as scratch:
        tree = Path(scratch)
        subprocess.run(['dpkg-deb', '-x', str(deb), str(tree)], check=True)
        root = tree if roothide else tree / 'var/jb'
        require((root / 'usr/bin').is_dir(), 'missing usr/bin in expected layout')
        if roothide:
            require(not (root / 'var/jb').exists(), 'RootHide package contains rootless tree')
        else:
            require(not (tree / 'usr').exists(), 'rootless package contains unprefixed usr')
        executables = libraries = scripts = 0
        for item in tree.rglob('*'):
            if item.is_symlink() or not item.is_file():
                continue
            with item.open('rb') as stream:
                header = stream.read(32)
            relative = str(item.relative_to(root))
            if header.startswith(b'#!') and os.access(item, os.X_OK):
                expected = '#!' + ('' if roothide else '/var/jb') + '/bin/sh'
                require(item.read_text().splitlines()[0] == expected,
                        f'{relative}: wrong script interpreter')
                require('@PREFIX@' not in item.read_text(), f'{relative}: unresolved prefix')
                scripts += 1
            if not header.startswith(b'\xcf\xfa\xed\xfe'):
                continue
            require(os.access(item, os.X_OK), f'{relative}: Mach-O lacks execute mode')
            require(run('lipo', '-archs', str(item)) == 'arm64', f'{relative}: wrong CPU')
            build = run('vtool', '-show-build', str(item))
            require(re.search(r'^\s*platform (IOS|2)$', build, re.M), f'{relative}: not iOS')
            dependencies = run('otool', '-L', str(item)).splitlines()[1:]
            dependencies = [line.strip().split(' (compatibility')[0] for line in dependencies]
            vroot = any('libvroot' in dep for dep in dependencies)
            if not roothide:
                require(not vroot, f'{relative}: rootless loads vroot')
            else:
                require(not any(dep.startswith('/var/jb/') for dep in dependencies),
                        f'{relative}: RootHide dependency uses /var/jb')
            filetype = int.from_bytes(header[12:16], 'little')
            if filetype == 2:  # MH_EXECUTE
                executables += 1
                signed = subprocess.check_output(['ldid', '-e', str(item)])
                entitlements = plistlib.loads(signed)
                for key in ENTITLEMENTS:
                    require(entitlements.get(key) is True, f'{relative}: missing {key}')
                require(entitlements.get('com.apple.private.security.container-required') is False,
                        f'{relative}: container-required must be false')
                if package == 'wiki.qaq.codex':
                    require(entitlements.get('com.apple.developer.kernel.extended-virtual-addressing') is True,
                            f'{relative}: missing V8 address-space entitlement')
                if package in VROOT_PACKAGES:
                    require(vroot == roothide, f'{relative}: wrong vroot flavor')
                    if roothide:
                        require('@loader_path/.jbroot/usr/lib/libvrootapi.dylib' in dependencies,
                                f'{relative}: wrong vroot loader path')
            else:
                libraries += 1
        require(executables > 0, 'no executable payload')
        if package == 'wiki.qaq.fish':
            for alias in ['fish_indent', 'fish_key_reader']:
                require(os.path.samefile(root / 'usr/bin/fish', root / 'usr/bin' / alias),
                        f'{alias}: not a hard link to final fish')
        if package == 'wiki.qaq.claude':
            require((root / 'usr/libexec/claude/s.dylib').is_file(), 'Claude shim missing')
        if package == 'wiki.qaq.kk':
            require((root / 'usr/libexec/kk/kwwk_KWWKAI.bundle').is_dir(), 'kk catalog missing')
        print(f'PASS {deb.name}: {executables} executable(s), {libraries} library/libraries, {scripts} script(s)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', nargs='+', type=Path)
    args = parser.parse_args()
    failures = 0
    for package_file in args.packages:
        try:
            audit(package_file)
        except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
            failures += 1
            print(f'FAIL {package_file.name}: {error}')
    raise SystemExit(bool(failures))
