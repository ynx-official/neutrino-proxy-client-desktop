#!/usr/bin/env bash
set -euo pipefail

tag="${1:?release tag is required}"
python3 scripts/release.py metadata --tag "$tag"
app="build/macos/Build/Products/Release/Neutrino.app"
output="release-assets"
base="neutrino-proxy-client-desktop-${tag}-macos-universal"
test -d "$app"

# Verify every Mach-O slice, including Flutter and plugin frameworks.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    lipo "$binary" -verify_arch x86_64 arm64
  fi
done < <(find "$app" -type f -print0)
lipo "$app/Contents/MacOS/Neutrino" -verify_arch x86_64 arm64
codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$base.zip"
unzip -tq "$output/$base.zip"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Neutrino.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Neutrino -srcfolder "$staging" -ov -format UDZO "$output/$base.dmg"
hdiutil verify "$output/$base.dmg"
