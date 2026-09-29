#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
release_root="${1:?Supply a NEW release directory; existing output is refused}"
icon_source="${2:-$source_dir/Assets/IconCandidates/LayeredC.png}"
if [ ! -f "$icon_source" ]; then echo "Icon source not found: $icon_source" >&2; exit 1; fi
if [ -e "$release_root" ]; then echo "Refusing existing release destination: $release_root" >&2; exit 1; fi
mkdir -p "$release_root"
git -C "$source_dir" rev-parse HEAD > "$release_root/source-revision.txt"
git -C "$source_dir" status --porcelain > "$release_root/source-status.txt"
printf '%s\n' "$icon_source" > "$release_root/icon-source.txt"
stage_dir="$HOME/Library/Application Support/Context Cleaner Development/Builds/$(uuidgen)"
mkdir -p "$stage_dir"
app="$stage_dir/Context Cleaner.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# No cleanup trap. Every stage, failed build and previous release is preserved.
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -Xlinker -no_adhoc_codesign \
 "$source_dir/Sources/Planner.swift" "$source_dir/Sources/Contents.swift" "$source_dir/Sources/Domain.swift" "$source_dir/Sources/Classifier.swift" "$source_dir/Sources/Store.swift" "$source_dir/Sources/Inventory.swift" \
 "$source_dir/Sources/Activity.swift" "$source_dir/Sources/OverviewData.swift" "$source_dir/Sources/Coverage.swift" "$source_dir/Sources/Design.swift" "$source_dir/Sources/Settings.swift" "$source_dir/Sources/Dashboard.swift" "$source_dir/Sources/ContentsBrowser.swift" "$source_dir/Sources/Model.swift" "$source_dir/Sources/App.swift" \
 -framework SwiftUI -framework AppKit -framework Charts -o "$app/Contents/MacOS/ContextCleaner"
iconset="$stage_dir/ContextCleaner.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
 sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
 double=$((size * 2))
 sips -z "$double" "$double" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/ContextCleaner.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ContextCleaner</string>
<key>CFBundleIdentifier</key><string>local.contextcleaner.mac</string>
<key>CFBundleName</key><string>Context Cleaner</string>
<key>CFBundleIconFile</key><string>ContextCleaner</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.12.0</string>
<key>CFBundleVersion</key><string>25</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign with a stable identity when one exists, so macOS keeps your privacy answers (Documents, other apps' data)
# across updates. Set CC_SIGN_IDENTITY to choose one, or "-" for ad-hoc. Falls back to ad-hoc if signing fails.
sign_identity="${CC_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID Application/ { print $2; exit }')}"
if [ -n "$sign_identity" ] && [ "$sign_identity" != "-" ] && codesign --force --sign "$sign_identity" --timestamp=none "$app" 2>/dev/null; then
  echo "Signed with identity $sign_identity"
else
  codesign --force --sign - "$app"; echo "Signed ad-hoc"
fi
codesign --verify --deep --strict "$app"
package_dir="$stage_dir/Package"
mkdir "$package_dir"
ditto "$app" "$package_dir/Context Cleaner.app"
ln -s /Applications "$package_dir/Applications"
printf '%s\n' "$stage_dir" > "$release_root/build-stage.txt"
hdiutil create -volname 'Context Cleaner 0.12.0' -srcfolder "$package_dir" -format UDZO "$release_root/Context-Cleaner-0.12.0.dmg"
hdiutil verify "$release_root/Context-Cleaner-0.12.0.dmg"
shasum -a 256 "$release_root/Context-Cleaner-0.12.0.dmg" > "$release_root/SHA256SUMS.txt"
printf 'App retained at: %s\n' "$app"
