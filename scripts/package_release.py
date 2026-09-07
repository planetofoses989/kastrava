#!/usr/bin/env python3
"""
Package Kastrava for distribution via the custom zip installer.
Run: python3 scripts/package_release.py

Produces: release/Kastrava-27.0.0.zip
  - install.py
  - Kastrava-release.zip (scrambled with XOR cipher, contains dist/ output)
"""

import os, sys, subprocess, zipfile

RELEASE_DIR = os.path.join(os.path.dirname(__file__), '..')
DIST_DIR = os.path.join(RELEASE_DIR, 'dist')
OUT_DIR = os.path.join(RELEASE_DIR, 'release')
INSTALL_SCRIPT = os.path.join(RELEASE_DIR, 'install.py')
PASSWORD = b'kastra27#secure!rel'

def get_version():
    pkg = os.path.join(RELEASE_DIR, 'package.json')
    with open(pkg) as f:
        import json
        return json.load(f)['version']

def build():
    print('[Package] Building webpack...')
    result = subprocess.run(
        ['npx', 'webpack', '--config', 'webpack.config.js'],
        cwd=RELEASE_DIR, capture_output=True, text=True
    )
    if result.returncode != 0:
        print('[Package] Build failed:')
        print(result.stdout + result.stderr)
        sys.exit(1)
    print('[Package] Build succeeded')

def xor_scramble(data, key):
    return bytes(data[i] ^ key[i % len(key)] for i in range(len(data)))

def create_release_zip(version):
    print('[Package] Creating Kastrava-release.zip ...')
    zip_path = os.path.join(OUT_DIR, 'Kastrava-release.zip')
    os.makedirs(OUT_DIR, exist_ok=True)

    import io
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(DIST_DIR):
            for fn in files:
                fpath = os.path.join(root, fn)
                arcname = os.path.relpath(fpath, RELEASE_DIR)
                zf.write(fpath, arcname)
        pkg_json = os.path.join(RELEASE_DIR, 'package.json')
        zf.write(pkg_json, 'package.json')
    raw = buf.getvalue()
    scrambled = xor_scramble(raw, PASSWORD)
    with open(zip_path, 'wb') as f:
        f.write(scrambled)
    size_mb = os.path.getsize(zip_path) / (1024 * 1024)
    print(f'[Package] Scrambled release zip: {zip_path} ({size_mb:.1f} MB)')
    return zip_path

def create_distribution_zip(version, release_zip):
    out_name = f'Kastrava-{version}.zip'
    out_path = os.path.join(OUT_DIR, out_name)
    print(f'[Package] Creating {out_name} ...')
    if not os.path.exists(INSTALL_SCRIPT):
        print(f'[Package] ERROR: {INSTALL_SCRIPT} not found')
        sys.exit(1)
    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.write(INSTALL_SCRIPT, 'install.py')
        zf.write(release_zip, 'Kastrava-release.zip')
    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f'[Package] Distribution zip: {out_path} ({size_mb:.1f} MB)')

def main():
    os.chdir(RELEASE_DIR)
    version = get_version()
    print(f'[Package] Packaging Kastrava v{version}')
    build()
    release_zip = create_release_zip(version)
    create_distribution_zip(version, release_zip)
    print(f'\n[Package] Done! Distribution: release/Kastrava-{version}.zip')

if __name__ == '__main__':
    main()
