#!/usr/bin/env python3
# download_emnist.py
# Download EMNIST Letters IDX files for offline MLTest training.

import argparse
import gzip
import hashlib
import shutil
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'e1ce0ec731a6482d8a708c641c2030d6a6cc1f31'
BASE_URL = f'https://huggingface.co/datasets/Heliosoph/EMNIST/resolve/{REVISION}'
# Published SHA-256 values from the immutable mirror commit's Git LFS pointers:
# https://huggingface.co/datasets/Heliosoph/EMNIST/commit/e1ce0ec731a6482d8a708c641c2030d6a6cc1f31
FILES = {
    'emnist-letters-train-images-idx3-ubyte.gz': ('6288f418a917e007bf5fddb823a2dc7a5c6a35031401b93292a539cb12bd881f', 124800, 2051),
    'emnist-letters-train-labels-idx1-ubyte.gz': ('9759af91ea6bccdf07a6040fd085861f2ec88e37f7c3f5760f6feb57106fbe5c', 124800, 2049),
    'emnist-letters-test-images-idx3-ubyte.gz':  ('50f0e93d75b99b463e9760b8345866f22587fa2c2fba472730a5ba09c693412d', 20800, 2051),
    'emnist-letters-test-labels-idx1-ubyte.gz':  ('924955c31fe7fd809b7303b5c0141282955f4b8390c74cdfd5d80435e0f4b4cb', 20800, 2049),
}

def checksum(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def verify_idx_gz(path: Path, count: int, magic: int) -> None:
    """Validate the IDX header, full decompression and uncompressed byte count."""
    with gzip.open(path, 'rb') as f:
        if magic == 2051:
            header = f.read(16)
            if len(header) != 16:
                raise ValueError(f'{path.name}: truncated image header')
            got_magic, n, rows, cols = struct.unpack('>IIII', header)
            if (got_magic, n, rows, cols) != (2051, count, 28, 28):
                raise ValueError(f'{path.name}: unexpected image IDX shape/header')
            expected = count * 28 * 28
        else:
            header = f.read(8)
            if len(header) != 8:
                raise ValueError(f'{path.name}: truncated labels header')
            got_magic, n = struct.unpack('>II', header)
            if (got_magic, n) != (2049, count):
                raise ValueError(f'{path.name}: unexpected label IDX header')
            expected = count
        seen = 0
        while True:
            block = f.read(1024 * 1024)
            if not block:
                break
            seen += len(block)
            if magic == 2049 and any(b < 1 or b > 26 for b in block):
                raise ValueError(f'{path.name}: expected EMNIST Letters labels 1 through 26')
        if seen != expected:
            raise ValueError(f'{path.name}: expected {expected:,} data bytes, got {seen:,}')

def validate(path: Path, expected_sha: str, count: int, magic: int) -> None:
    actual = checksum(path)
    if actual != expected_sha:
        raise ValueError(f'{path.name}: SHA-256 mismatch: expected {expected_sha}, got {actual}')
    verify_idx_gz(path, count, magic)

def download_one(url: str, dest: Path, timeout: float) -> None:
    """Download atomically; never leave half-downloaded final files."""
    tmp = dest.with_name(dest.name + '.part')
    tmp.unlink(missing_ok=True)
    request = urllib.request.Request(url, headers={
        'Accept': 'application/octet-stream',
    })
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response, tmp.open('wb') as out:
            total = int(response.headers.get('Content-Length', 0) or 0)
            got = 0
            next_update = 5 * 1024 * 1024
            while block := response.read(1024 * 1024):
                out.write(block)
                got += len(block)
                if got >= next_update:
                    suffix = f' / {total / 1048576:.1f} MiB' if total else ''
                    print(f'  {got / 1048576:.1f} MiB{suffix}', flush=True)
                    next_update += 5 * 1024 * 1024
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    tmp.replace(dest)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Download EMNIST Letters independently of MLTest model training.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument('--output-dir', type=Path, default=ROOT/'tools'/'emnist',
                        help='Folder for the four compressed IDX files')
    parser.add_argument('--base-url', default=BASE_URL,
                        help='Base URL containing the individual EMNIST Letters .gz files')
    parser.add_argument('--force', action='store_true', help='Re-download files, even if already valid')
    parser.add_argument('--verify-only', action='store_true', help='Verify existing files; do not download')
    parser.add_argument('--timeout', type=float, default=120, help='HTTP response timeout in seconds')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if args.force and args.verify_only:
        parser.error('--force and --verify-only cannot be combined')
    return args

def main() -> None:
    args = parse_args()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f'EMNIST Letters directory: {output_dir}', flush=True)
    print(f'Source: {args.base_url}', flush=True)
    for name, (digest, count, magic) in FILES.items():
        destination = output_dir/name
        if destination.exists() and not args.force:
            try:
                validate(destination, digest, count, magic)
                print(f'OK (cached): {name}', flush=True)
                continue
            except (ValueError, OSError, EOFError) as exc:
                if args.verify_only:
                    raise ValueError(f'Invalid cached file: {exc}') from exc
                print(f'Invalid cache ({name}): {exc}; downloading again', flush=True)
        if args.verify_only:
            raise ValueError(f'Missing file: {destination}')
        url = f'{args.base_url.rstrip("/")}/{name}'
        print(f'Downloading {name}...', flush=True)
        # Preserve a valid existing file until replacement is ready.
        staged = destination.with_name(destination.name + '.new')
        try:
            download_one(url, staged, args.timeout)
            validate(staged, digest, count, magic)
            staged.replace(destination)
        finally:
            staged.unlink(missing_ok=True)
        print(f'OK (verified): {name}', flush=True)
    print('Complete. You can now train offline with tools/train_model.py', flush=True)

if __name__ == '__main__':
    try:
        main()
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError, OSError, EOFError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        print('If your network blocks downloads, download the four .gz files in a browser '
              'to tools/emnist/ and rerun with --verify-only.', file=sys.stderr)
        raise SystemExit(1) from exc
