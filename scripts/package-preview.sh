#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "A macOS build host with Xcode Command Line Tools is required." >&2
  exit 1
fi
for tool in xcrun codesign ditto shasum plutil; do
  command -v "$tool" >/dev/null
done
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid bundle version" >&2; exit 1; }
# Clean only ignored build outputs. The source plist is never modified.
make clean
make test
make app ARCH_FLAGS='-arch arm64 -arch x86_64'
app='dist/Token Bar.app'
binary="$app/Contents/MacOS/TokenBar"
plutil -lint "$app/Contents/Info.plist"
xcrun lipo "$binary" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv "$app" 2>&1 | grep -q 'Signature=adhoc'
# Enforce portable system dependencies, rather than a developer's Homebrew paths.
xcrun otool -L "$binary" > .build/dependencies.txt
if grep -E '^[[:space:]]+/' .build/dependencies.txt | grep -Ev '^[[:space:]]+(/System/Library/|/usr/lib/)'; then
  echo "Unexpected non-system dependency" >&2
  exit 1
fi
archive="Codex-Token-Bar-${version}-preview-universal-macos.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
# Verify the transported bundle, not just the original build.
verify_dir=$(mktemp -d)
trap 'rm -rf "$verify_dir"' EXIT
ditto -x -k "dist/$archive" "$verify_dir"
codesign --verify --deep --strict --verbose=2 "$verify_dir/Token Bar.app"
xcrun lipo "$verify_dir/Token Bar.app/Contents/MacOS/TokenBar" -verify_arch arm64 x86_64
(cd dist && shasum -a 256 "$archive" > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
{
  echo "Candidate only: ad-hoc signed; NOT notarized; NOT approved for publication."
  echo "Version: $version"
  echo "Source commit: $(git rev-parse HEAD)"
  echo "Source status (must be empty for release):"
  git status --porcelain
  sw_vers
  xcrun clang --version
  xcrun lipo -archs "$binary"
  cat .build/dependencies.txt
  echo "Automated checks passed. GUI, Codex integration and downloaded-app checks still required."
} > dist/BUILD-INFO.txt
printf 'Candidate ready for manual testing: dist/%s\n' "$archive"
