#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET="arm64-apple-macosx14.0"
COMMON=(
  -sdk "$SDK"
  -target "$TARGET"
  -swift-version 5
  -framework AppKit
  -framework ApplicationServices
  -framework ScreenCaptureKit
  -framework Carbon
  -framework SwiftUI
  -framework CoreGraphics
)

echo "logic tests"
swiftc "${COMMON[@]}" -parse-as-library -o /tmp/Taber-logic-tests \
  Taber/Support/DisplayLayout.swift \
  Taber/Support/Shortcut.swift \
  Taber/Support/MRU.swift \
  Taber/Support/TrayMenu.swift \
  Taber/Support/ThumbnailSizing.swift \
  Taber/Windows/InventoryAssembler.swift \
  Tests/LogicTests.swift
/tmp/Taber-logic-tests

echo "app"
APP="build/Taber.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc "${COMMON[@]}" -parse-as-library -O -o "$APP/Contents/MacOS/Taber" \
  Taber/App/TaberApp.swift \
  Taber/App/PermissionsView.swift \
  Taber/Hotkey/HotkeyMonitor.swift \
  Taber/Windows/WindowInventory.swift \
  Taber/Windows/WindowActivator.swift \
  Taber/Windows/WindowAX.swift \
  Taber/Windows/WindowSpaces.swift \
  Taber/Windows/InventoryAssembler.swift \
  Taber/Thumbnails/ThumbnailCache.swift \
  Taber/Switcher/SwitcherPanel.swift \
  Taber/Switcher/SwitcherController.swift \
  Taber/Settings/SettingsView.swift \
  Taber/Settings/SettingsStore.swift \
  Taber/Support/DisplayLayout.swift \
  Taber/Support/Shortcut.swift \
  Taber/Support/MRU.swift \
  Taber/Support/TrayMenu.swift \
  Taber/Support/ThumbnailSizing.swift
mkdir -p "$APP/Contents/Resources"
cp Taber/Info.plist "$APP/Contents/Info.plist"
cp Taber/Assets/Taber.icns "$APP/Contents/Resources/Taber.icns"
IDENTITY="${TABER_SIGN_IDENTITY:-Taber Local Codesign}"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier local.taber.Taber "$APP"
else
  echo "没有找到稳定签名证书「$IDENTITY」，退回临时签名。重新编译后需要再次授权。" >&2
  codesign --force --sign - --identifier local.taber.Taber "$APP"
fi
echo "built $APP"
