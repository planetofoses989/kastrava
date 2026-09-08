#!/usr/bin/env bash
# Build the Arch Linux package for Kastrava.
# Run: bash scripts/build_arch.sh   (from repo root)
set -e
cd "$(dirname "$0")/.."

VERSION=$(node -p "require('./package.json').version")
echo "[arch] syncing PKGBUILD to v$VERSION"
sed -i -E "s/^pkgver=.*/pkgver=$VERSION/" packaging/arch/PKGBUILD

echo "[arch] refreshing linux-unpacked..."
npx electron-builder --linux dir

echo "[arch] running makepkg..."
rm -f packaging/arch/*.pkg.tar.zst
(cd packaging/arch && makepkg -f)

echo "[arch] moving artifact to release/..."
mv packaging/arch/kastrava-*.pkg.tar.zst release/
ls -la release/*.pkg.tar.zst
echo "[arch] done"
