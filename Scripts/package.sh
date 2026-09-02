#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
dist_dir="$repo_dir/dist"
app_dir="$repo_dir/build/Refill.app"

if [[ -n "${REFILL_NOTARY_PROFILE:-}" && -z "${REFILL_SIGNING_IDENTITY:-}" ]]; then
  echo "REFILL_SIGNING_IDENTITY is required when notarizing." >&2
  exit 1
fi

"$repo_dir/build.sh" --universal >/dev/null
REFILL_EXPECT_UNIVERSAL=1 "$repo_dir/Scripts/verify-build.sh" >/dev/null

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
archive="$dist_dir/Refill-${version}-macOS-universal.zip"
checksum="$archive.sha256"
/bin/mkdir -p "$dist_dir"
if [[ -f "$archive" ]]; then /bin/rm "$archive"; fi
if [[ -f "$checksum" ]]; then /bin/rm "$checksum"; fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"

if [[ -n "${REFILL_NOTARY_PROFILE:-}" ]]; then
  /usr/bin/xcrun notarytool submit "$archive" \
    --keychain-profile "$REFILL_NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$app_dir"
  /usr/bin/xcrun stapler validate "$app_dir"
  /bin/rm "$archive"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"
fi

(
  cd "$dist_dir"
  /usr/bin/shasum -a 256 "${archive:t}" > "${checksum:t}"
)

echo "$archive"
echo "$checksum"
