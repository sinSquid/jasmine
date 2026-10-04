#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
: "${KEY_FILE_BASE64:?Missing signing key}"
: "${KEY_PASSWORD:?Missing signing password}"
: "${ANDROID_HOME:?Missing Android SDK}"
APKSIGNER="${APKSIGNER:-$ANDROID_HOME/build-tools/30.0.2/apksigner}"
APK="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
test -x "$APKSIGNER"
test -f "$APK"
umask 077
SIGN_DIR=$(mktemp -d)
trap 'rm -rf "$SIGN_DIR"' EXIT HUP INT TERM
printf '%s' "$KEY_FILE_BASE64" | base64 -d > "$SIGN_DIR/key.jks"
export KEY_PASSWORD
"$APKSIGNER" sign --ks "$SIGN_DIR/key.jks" --ks-pass env:KEY_PASSWORD "$APK"
