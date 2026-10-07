#!/usr/bin/env bash
# Checks an APK for Google Play's 16 KB memory page size rule (required for
# apps targeting Android 15+): every 64-bit native library must have 16 KB
# aligned ELF segments and be 16 KB aligned inside the APK.
# Usage: tool/check_16kb.sh path/to/app.apk
set -euo pipefail
apk="$1"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$apk" 'lib/arm64-v8a/*' 'lib/x86_64/*' -d "$tmp" 2>/dev/null || true
bad=0
while IFS= read -r so; do
  # Smallest LOAD segment alignment, e.g. 0x4000 = 16 KB.
  min=""
  for a in $(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }'); do
    a=$((a))
    if [ -z "$min" ] || [ "$a" -lt "$min" ]; then min=$a; fi
  done
  if [ -z "$min" ] || [ "$min" -lt 16384 ]; then
    echo "::error::${so#"$tmp"/} has ${min:-no} byte ELF alignment, needs 16384"
    bad=1
  fi
done < <(find "$tmp" -name '*.so')
zipalign=$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/nonexistent}}"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$zipalign" ]; then
  if ! "$zipalign" -c -P 16 4 "$apk" >/dev/null; then
    echo "::error::$(basename "$apk") native libraries are not 16 KB aligned in the zip"
    bad=1
  fi
fi
[ "$bad" -eq 0 ] && echo "16 KB page size check passed: $(basename "$apk")"
exit "$bad"
