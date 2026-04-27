#!/usr/bin/env bash
# build-atmosphere-mpv-player.sh — build the ATMOSphere-MPV APK and
# copy it into the parent ATMOSphere prebuilt-apps tree.
#
# Usage:
#     bash device/rockchip/atmosphere/mpv-player/build-atmosphere-mpv-player.sh
#
# Output:
#     device/rockchip/rk3588/prebuilt_apps/atmosphere-mpv-player.apk
#
# Native libraries: pre-built libmpv + FFmpeg .so files are already
# committed in app/src/main/jniLibs/<abi>/ (libmpv.so, libavcodec.so,
# libavformat.so, libavfilter.so, libavutil.so, libswresample.so,
# libswscale.so, libavdevice.so, libplayer.so, libc++_shared.so).
# No NDK / libmpv-android-buildsystem run is needed; gradle just packages
# them. If they're ever missing or stale, run buildscripts/buildall.sh
# inside this submodule first (one-time, expensive).
#
# Signing: AGP defaults to -unsigned for release builds when no
# signingConfigs block exists. AOSP re-signs at image-assembly time
# via LOCAL_CERTIFICATE := platform in prebuilt_apps/Android.mk.
#
# JDK: gradle 8.14.3 + AGP 8.13.2 require Java 21+. Same JDK pick path
# as TorrServe (gradle 8.11.1) — both are >=8.5 so jdk21 first.
#
# applicationId: deliberately preserved as "is.xyz.mpv" — see Fix #124
# rationale (renaming wipes /data/data/is.xyz.mpv/ — playlists, mpv.conf,
# bookmarks). Display label is rebranded via @string/mpv_activity to
# "ATMOSphere MPV Player" across all 14 locales.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

cd "$SCRIPT_DIR"

echo "[ATMOSphere-MPV] build-atmosphere-mpv-player.sh"
echo "  script dir: $SCRIPT_DIR"
echo "  parent:     $PARENT_ROOT"

# Ensure gradle wrapper is +x (some clones drop the bit).
[ -f ./gradlew ] && chmod +x ./gradlew 2>/dev/null || true

# Sanity check: jniLibs must be present, otherwise the resulting APK
# would have no native libraries and MPV would crash at startup with
# UnsatisfiedLinkError on libmpv.so.
_JNI_ARM64=app/src/main/jniLibs/arm64-v8a
if [ ! -f "$_JNI_ARM64/libmpv.so" ]; then
    echo "[ATMOSphere-MPV] ERROR: $_JNI_ARM64/libmpv.so missing."
    echo "  Run buildscripts/buildall.sh inside this submodule first to populate"
    echo "  jniLibs/ from upstream FFmpeg + libmpv sources. That is a one-time,"
    echo "  expensive operation; once the .so files exist they are committed."
    exit 2
fi

# Pick a JDK ≥ 21 (gradle 8.14.3 + AGP 8.13.2 require it).
_pick_jdk21() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        _v=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)
        case "$_v" in
            *'"21'*|*'"22'*|*'"23'*|*'"24'*|*'"25'*)
                return 0 ;;
        esac
    fi
    for cand in \
        "$PARENT_ROOT/prebuilts/jdk/jdk21/linux-x86" \
        "$PARENT_ROOT/prebuilts/jdk/jdk21" \
        /usr/lib/jvm/java-21-openjdk \
        /usr/lib/jvm/java-21-openjdk-*.x86_64 \
        /usr/lib/jvm/jre-21-openjdk; do
        for actual in $cand; do
            if [ -x "$actual/bin/java" ]; then
                export JAVA_HOME="$actual"
                return 0
            fi
        done
    done
    echo "[ATMOSphere-MPV] WARNING: no JDK 21 found — gradle 8.14.3 may fail on older Java"
    return 1
}
_pick_jdk21 || true
if [ -n "${JAVA_HOME:-}" ]; then
    echo "[ATMOSphere-MPV] JAVA_HOME=$JAVA_HOME"
    "$JAVA_HOME/bin/java" -version 2>&1 | head -1
fi

# local.properties — gradle needs sdk.dir to point at the Android SDK.
# The submodule already has a static local.properties pinned to
# /home/milosvasic/Android/Sdk; if missing or pointing elsewhere we
# regenerate from the user's home or ANDROID_HOME.
if [ ! -f local.properties ] || ! grep -q '^sdk.dir=' local.properties; then
    _SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
    if [ -d "$_SDK" ]; then
        echo "[ATMOSphere-MPV] writing local.properties (sdk.dir=$_SDK)"
        echo "sdk.dir=$_SDK" > local.properties
    fi
fi

# Build the universal release APK (default flavor). The "default"
# product flavor is the one we want; "api29" is an old-API back-compat
# variant and not relevant for ATMOSphere (compileSdk 35 / targetSdk 35).
echo "[ATMOSphere-MPV] running: ./gradlew :app:assembleDefaultRelease"
bash ./gradlew :app:assembleDefaultRelease --no-daemon --console=plain

# Locate the resulting universal APK. AGP names it
# app-default-universal-release-unsigned.apk when no signingConfig is
# present, app-default-universal-release-signed.apk when a debug
# keystore signs it. Either is fine because AOSP re-signs at
# image-assembly via LOCAL_CERTIFICATE := platform.
APK_PATH=""
for cand in \
    app/build/outputs/apk/default/release/app-default-universal-release-unsigned.apk \
    app/build/outputs/apk/default/release/app-default-universal-release-signed.apk \
    app/build/outputs/apk/default/release/app-default-universal-release.apk; do
    if [ -f "$cand" ]; then
        APK_PATH="$cand"
        break
    fi
done

# Reject per-ABI APKs ending in arm64-v8a / armeabi-v7a / x86 / x86_64
# even if found — we want the universal APK so all abis are bundled
# (matches the historical atmosphere-mpv-player.apk shape).
if [ -z "${APK_PATH:-}" ]; then
    echo "[ATMOSphere-MPV] ERROR: gradle reported success but no universal APK found."
    echo "  Listing apk/default/release/:"
    ls -la app/build/outputs/apk/default/release/ 2>&1 | head -20
    exit 3
fi
case "$APK_PATH" in
    *armeabi-v7a*|*arm64-v8a*release-unsigned.apk|*x86*release.apk|*x86_64*)
        echo "[ATMOSphere-MPV] ERROR: matched a per-ABI APK ($APK_PATH); aborting"
        exit 4 ;;
esac

OUT="$PARENT_ROOT/device/rockchip/rk3588/prebuilt_apps/atmosphere-mpv-player.apk"

echo "[ATMOSphere-MPV] copying $APK_PATH"
echo "             →  $OUT"
cp -f "$APK_PATH" "$OUT"

# Verify the copy by aapt-checking the application label so the build
# fails loudly if a stale APK lands here.
#
# Pipeline-trap warning: `set -euo pipefail` + `aapt | grep -m1 | sed`
# triggers SIGPIPE on aapt when grep exits early, the pipeline returns
# non-zero, set -e aborts. Workaround: capture aapt output once with
# `|| true`, then use bash parameter expansion (no pipes).
AAPT=""
for cand in "$HOME/Android/Sdk/build-tools/"*/aapt \
            /opt/android-sdk/build-tools/*/aapt \
            "${ANDROID_HOME:-}/build-tools/"*/aapt; do
    for actual in $cand; do
        if [ -x "$actual" ]; then AAPT="$actual"; break 2; fi
    done
done
if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
    RAW=$("$AAPT" dump badging "$OUT" 2>/dev/null) || true
    LABEL=${RAW#*$'\napplication-label:\''}
    [ "$LABEL" = "$RAW" ] && LABEL=${RAW#*application-label:\'}
    LABEL=${LABEL%%\'*}
    case "$LABEL" in
        ATMOSphere*)
            echo "[ATMOSphere-MPV] verified application-label='$LABEL' ✓" ;;
        *)
            echo "[ATMOSphere-MPV] ERROR: shipped APK label='$LABEL' (expected 'ATMOSphere MPV Player')"
            exit 5 ;;
    esac
else
    echo "[ATMOSphere-MPV] WARNING: aapt not found — skipping post-build label verification"
fi

echo "[ATMOSphere-MPV] done."
