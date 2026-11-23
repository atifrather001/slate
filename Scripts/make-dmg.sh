#!/bin/zsh
# Builds Slate and packs it into a disk image beside this project, for installing on this Mac.
# The app is signed for this Mac only; sharing it would need a Developer ID and notarization.
set -euo pipefail
cd "${0:A:h}/.."

./Scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/NotepadPlusPlusMac/Resources/Info.plist)
dmg="../Slate-$version.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

ditto .build/app/Slate.app "$staging/Slate.app"
ln -s /Applications "$staging/Applications"
if [[ -e "$dmg" ]]; then
  echo "$dmg already exists. Move it away first." >&2
  exit 1
fi
hdiutil create -volname "Slate $version" -srcfolder "$staging" -format UDZO -fs APFS "$dmg" -quiet
echo "Made ${dmg:A}"
