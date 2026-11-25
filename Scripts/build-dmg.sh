#!/bin/bash
# Builds Camfeed, signs it for Developer ID distribution and packs a DMG.
# Usage: Scripts/build-dmg.sh [--notarize <keychain-profile>]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

team="63QQLP356Q"
# Two certificates share this name in the login keychain, so sign by fingerprint.
identity="$(security find-identity -p codesigning -v | awk '/Developer ID Application/ {print $2; exit}')"
if [[ -z "$identity" ]]; then
	echo "no Developer ID Application identity in the keychain" >&2
	exit 1
fi
build="$root/build"
archive="$build/Camfeed.xcarchive"
export="$build/export"
app="$export/Camfeed.app"
dmg="$build/Camfeed.dmg"
staging="$build/dmg"

notary_profile=""
if [[ "${1:-}" == "--notarize" ]]; then
	notary_profile="${2:?a notarytool keychain profile is required}"
fi

echo "==> Archiving"
rm -rf "$archive" "$export" "$staging"
xcodebuild archive \
	-project Camfeed.xcodeproj \
	-scheme Camfeed \
	-configuration Release \
	-archivePath "$archive" \
	-allowProvisioningUpdates \
	CODE_SIGN_STYLE=Automatic \
	DEVELOPMENT_TEAM="$team" >/dev/null

echo "==> Exporting with Developer ID signing"
xcodebuild -exportArchive \
	-archivePath "$archive" \
	-exportPath "$export" \
	-exportOptionsPlist Config/ExportOptions.plist \
	-allowProvisioningUpdates >/dev/null

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements - "$app" >/dev/null 2>&1
codesign -d --entitlements - "$app"/Contents/Library/SystemExtensions/*.systemextension >/dev/null 2>&1

echo "==> Staging DMG contents"
mkdir -p "$staging"
ditto "$app" "$staging/Camfeed.app"
ln -s /Applications "$staging/Applications"

echo "==> Creating $dmg"
rm -f "$dmg"
hdiutil create -volname "Camfeed" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
codesign --force --timestamp --sign "$identity" "$dmg"

if [[ -n "$notary_profile" ]]; then
	echo "==> Notarizing"
	xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
	xcrun stapler staple "$dmg"
	spctl --assess --type open --context context:primary-signature -vv "$dmg"
fi

echo "==> Done: $dmg"
shasum -a 256 "$dmg"
