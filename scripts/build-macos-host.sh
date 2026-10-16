#!/usr/bin/env bash
# Run after flutter build macos. Workers may come from the two native CI runners.
set -euo pipefail
app="${1:-build/macos/Build/Products/Release/Neutrino.app}"
workers="${2:-build/macos-workers}"
test "$(uname -s)" = Darwin
test -f "$app/Contents/MacOS/Neutrino"
mkdir -p "$workers" build/macos-host
native_arch="$(uname -m)"
worker_arch=x64
if [ "$native_arch" = arm64 ]; then worker_arch=arm64; fi
if [ ! -f "$workers/neutrino_worker_$worker_arch" ]; then
  destination="$(cd "$workers" && pwd)/neutrino_worker_$worker_arch"
  (cd services/proxy_worker && dart pub get --enforce-lockfile && dart compile exe bin/main.dart -o "$destination")
fi
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in x86_64 arm64; do
  xcrun swiftc -O -swift-version 5 -sdk "$sdk" -target "${arch}-apple-macosx12.0" \
    native/host_macos/main.swift -o "build/macos-host/host_$arch"
done
# Preserve the original Flutter executable. Re-running packaging is idempotent;
# re-run flutter build before reassembling a changed Flutter UI.
if otool -L "$app/Contents/MacOS/Neutrino" | grep -q FlutterMacOS; then
  mv -f "$app/Contents/MacOS/Neutrino" "$app/Contents/MacOS/neutrino_ui"
fi
test -f "$app/Contents/MacOS/neutrino_ui"
lipo -create build/macos-host/host_x86_64 build/macos-host/host_arm64 -output "$app/Contents/MacOS/Neutrino"
for worker in "$workers"/neutrino_worker_*; do
  test -f "$worker"
  cp "$worker" "$app/Contents/MacOS/"
  chmod +x "$app/Contents/MacOS/$(basename "$worker")"
done
cp assets/tray.png "$app/Contents/Resources/neutrino-tray.png"
for helper in "$app/Contents/MacOS/neutrino_"*; do
  codesign --force --sign - --identifier "cn.neutrino.neutrinoProxyClientDesktop.$(basename "$helper")" \
    --entitlements native/host_macos/Helper.entitlements "$helper"
done
codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
