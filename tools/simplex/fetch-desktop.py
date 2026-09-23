#!/usr/bin/env python3
"""Fetch checksum-pinned official SimpleX runtimes for desktop packaging."""
import argparse
import hashlib
from pathlib import Path
import urllib.request
import zipfile

PINS = {
    'windows-x86_64': 'cced05429faa370f69d606161c2d65c8093438803e9d6a56e0765d6e0dbfbdca',
    'macos-aarch64': '2d21e5972ac39d3c8492d045055edfb2fcd80d58272a56d4034d00c162afdefe',
    'macos-x86_64': '86f712af5515d8789248c7be47929ac6f104d0619cb45ec8aa11975b618961fe',
}


def fetch(target, dest):
    dest = Path(dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    archive = dest / 'runtime.zip'
    url = f'https://github.com/simplex-chat/simplex-chat-libs/releases/download/v7.0.2/simplex-chat-libs-{target}.zip'
    if not archive.exists():
        urllib.request.urlretrieve(url, archive)
    if hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() != PINS[target]:
        archive.unlink()
        raise RuntimeError('SimpleX runtime checksum mismatch')
    with zipfile.ZipFile(archive) as bundle:
        for entry in bundle.infolist():
            if not (dest / entry.filename).resolve().is_relative_to(dest):
                raise RuntimeError('Unsafe archive member')
        bundle.extractall(dest)
    return dest / 'libs'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=PINS)
    parser.add_argument('destination')
    args = parser.parse_args()
    print(fetch(args.target, args.destination))
