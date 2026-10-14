#!/usr/bin/env python3
"""Build independent CI groups, reusing only packages with identical inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from catalog import ROOT, modules, sha256, verify_package

GROUPS = ('native', 'cpp', 'minato', 'pasta')


def group_for(entry):
    if entry['id'] in ('minato', 'pasta'):
        return entry['id']
    return 'native' if entry['source']['path'] == 'native' else 'cpp'


def input_key(entry, tracked, toolchain, root=ROOT):
    prefixes = (entry['source']['path'] + '/', str(Path(entry['recipe']).parent) + '/',
                'scripts/', 'schemas/', 'tests/')
    if group_for(entry) == 'cpp':
        prefixes += ('recipes/cpp/',)
    names = {entry['recipe'], entry['instructions'], f"catalog/modules/{entry['id']}.json",
             'LICENSE', 'pyproject.toml', 'uv.lock', '.python-version',
             '.github/workflows/check.yml'}
    names.update(name for name in tracked if name.startswith(prefixes))
    payload = {'entry': entry, 'toolchain': toolchain, 'architectures': ['arm64', 'x86_64'],
               'files': {name: sha256(root / name) for name in sorted(names)}}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def package_name(entry):
    return f"{entry['id']}-{entry['version']}-r{entry['revision']}-macos-arm64_x86_64.zip"


def reuse(entry, key, cache, destination):
    record = cache / entry['id'] / 'record.json'
    if not record.exists():
        return False
    metadata = json.loads(record.read_text())
    if metadata['key'] != key:
        return False
    archive = record.parent / package_name(entry)
    if sha256(archive) != metadata['sha256']:
        raise ValueError(f"Corrupt package cache: {entry['id']}")
    verify_package(archive, entry)
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(archive, destination / archive.name)
    print(f"Reused verified package: {archive.name}", flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('key', 'build'))
    parser.add_argument('group', choices=GROUPS)
    args = parser.parse_args()
    entries = [entry for entry in modules() if entry['delivery'] == 'binary' and group_for(entry) == args.group]
    tracked = subprocess.check_output(['git', 'ls-files', '--recurse-submodules', '-z'], cwd=ROOT).decode().split('\0')
    def output(*cmd):
        return subprocess.check_output(cmd, text=True).strip()
    toolchain = {'clang': output('xcrun', 'clang', '--version'),
                 'sdk': output('xcrun', '--sdk', 'macosx', '--show-sdk-version'),
                 'macOS': platform.mac_ver()[0]}
    if args.group == 'native':
        toolchain['swift'] = output('xcrun', 'swift', '--version')
    if args.group in ('minato', 'pasta'):
        toolchain['rust'] = output('cargo', '+1.93.0', '--version')
    keys = {entry['id']: input_key(entry, tracked, toolchain) for entry in entries}
    if args.command == 'key':
        key = hashlib.sha256(json.dumps(keys, sort_keys=True).encode()).hexdigest()
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output_file:
            output_file.write(f'key={key}\n')
        return
    cache = ROOT / 'build/package-cache' / args.group
    destination = ROOT / 'dist'
    pending = [entry for entry in entries if not reuse(entry, keys[entry['id']], cache, destination)]
    if pending:
        if args.group == 'native':
            subprocess.run(['swift', 'test', '--package-path', 'native'], check=True, cwd=ROOT)
        elif args.group == 'minato':
            subprocess.run(['cargo', '+1.93.0', 'test', '--locked', '--features', 'cli'],
                           check=True, cwd=ROOT / 'sources/minato',
                           env={**os.environ, 'CARGO_PROFILE_TEST_OPT_LEVEL': '0'})
        elif args.group == 'pasta':
            subprocess.run(['cargo', '+1.93.0', 'test', '--locked', '-p', 'pasta_shiori', '-p', 'pasta_lua',
                            '-p', 'pasta_dsl', '-p', 'pasta_core'], check=True, cwd=ROOT / 'sources/pasta')
        else:
            subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests',
                            '-p', 'test_yaya_charset.py', '-v'], check=True, cwd=ROOT)
    for entry in pending:
        subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), entry['id'],
                        '--archs', 'arm64', 'x86_64'], check=True, cwd=ROOT)
        folder = cache / entry['id']
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        archive = destination / package_name(entry)
        shutil.copyfile(archive, folder / archive.name)
        (folder / 'record.json').write_text(json.dumps({'key': keys[entry['id']], 'sha256': sha256(archive)}))
    # ABI probes run again even when every package was reused.
    subprocess.run([sys.executable, str(ROOT / 'scripts/smoke_packages.py'),
                    *[str(destination / package_name(entry)) for entry in entries]], check=True, cwd=ROOT)


if __name__ == '__main__':
    main()
