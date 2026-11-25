#!/bin/zsh
# Builds .build/app/Slate.app. It does not install it.
# To update the installed app: quit it, then copy the result over /Applications/Slate.app.
set -euo pipefail
cd "${0:A:h}/.."

# A universal app (Apple silicon and Intel) needs Xcode's build system, not just the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
arches=(--arch arm64 --arch x86_64)
swift build -c release "${arches[@]}"
bin="$(swift build -c release "${arches[@]}" --show-bin-path)"
app=".build/app/Slate.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$bin/NotepadPlusPlusMac" "$app/Contents/MacOS/Slate"
# Debug symbols aren't needed to run Slate and would nearly double its size.
strip -S -x "$app/Contents/MacOS/Slate" 2>/dev/null
cp Sources/NotepadPlusPlusMac/Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
# Each package's resources, such as Highlightr's languages and themes.
for bundle in "$bin"/*_*.bundle(N); do
  ditto "$bundle" "$app/Contents/Resources/${bundle:t}"
done
for package in Highlightr swift-collections SwiftTerm; do
  for license in .build/checkouts/$package/LICENSE*(N); do
    install -m 644 "$license" "$app/Contents/Resources/Licenses/$package-${license:t}"
  done
done
# highlight.js ships inside Highlightr with its own license.
install -m 644 .build/checkouts/Highlightr/src/assets/highlighter/LICENSE "$app/Contents/Resources/Licenses/highlight.js-LICENSE"

# Signed for this Mac only. Sharing it needs an Apple Developer ID and notarization.
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built $PWD/$app"
