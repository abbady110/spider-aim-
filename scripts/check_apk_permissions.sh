#!/usr/bin/env bash
set -euo pipefail

# Check the actual merged binary, not only our source manifest. The bundled
# OCR model must not acquire network permission through a transitive SDK.
apk_path="${1:-build/app/outputs/flutter-apk/app-release.apk}"
apk_aapt_tool=""
for candidate in "${ANDROID_HOME:?Android SDK is required}"/build-tools/*/aapt; do
  if [[ -x "$candidate" ]]; then
    apk_aapt_tool="$candidate"
  fi
done
if [[ -z "$apk_aapt_tool" || ! -f "$apk_path" ]]; then
  printf 'APK or Android aapt tool is unavailable.\n' >&2
  exit 1
fi
apk_permissions="$("$apk_aapt_tool" dump permissions "$apk_path")"
printf '%s\n' "$apk_permissions"
case "$apk_permissions" in
  *"'android.permission.INTERNET'"*|*"'android.permission.ACCESS_NETWORK_STATE'"*)
    printf 'Forbidden network permission in merged APK.\n' >&2
    exit 1
    ;;
esac
printf 'PASS: built APK has no INTERNET or ACCESS_NETWORK_STATE permission.\n'
