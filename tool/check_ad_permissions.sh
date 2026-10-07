#!/usr/bin/env bash
# Checks that an ads-off APK (dart-define ADS=off) asks for no advertising
# permissions, so Play Console can be answered "No" for advertising ID.
# Usage: tool/check_ad_permissions.sh path/to/app.apk
set -euo pipefail
apk="$1"
aapt2=$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/nonexistent}}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
if [ -z "$aapt2" ]; then
  echo "::error::aapt2 not found in the Android SDK build-tools"
  exit 1
fi
found=$("$aapt2" dump permissions "$apk" | grep -E 'AD_ID|ACCESS_ADSERVICES' || true)
if [ -n "$found" ]; then
  echo "::error::$(basename "$apk") still asks for ad permissions:"
  echo "$found"
  exit 1
fi
echo "$(basename "$apk"): no ad permissions"
