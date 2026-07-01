#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
EXECUTABLE_PATH="$RELEASE_DIR/InpaintVideosApp"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/InpaintVideosApp-Info.plist"
PYTHON_SCRIPT_SOURCE="$ROOT_DIR/Scripts/watermark_pipeline.py"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="InpaintVideos.app"
DMG_PATH="$DIST_DIR/InpaintVideos-macos-arm64.dmg"
TEMP_ROOT="$(mktemp -d /private/tmp/inpaint-videos-release.XXXXXX)"
STAGING_APP="$TEMP_ROOT/$APP_NAME"
DMG_STAGE_DIR="$TEMP_ROOT/dmg-root"
VERIFY_MOUNT="$TEMP_ROOT/verify-mount"

cleanup() {
    if mount | /usr/bin/grep -q "on $VERIFY_MOUNT "; then
        /usr/bin/hdiutil detach "$VERIFY_MOUNT" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$TEMP_ROOT"
}

trap cleanup EXIT HUP INT TERM

resolve_signing_identity() {
    if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
        printf '%s' "$SIGNING_IDENTITY"
        return
    fi

    local identity
    identity="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '/Apple Development:/{print $2; exit}')"
    if [[ -n "$identity" ]]; then
        printf '%s' "$identity"
        return
    fi

    printf '%s' "-"
}

cd "$ROOT_DIR"

required_files=(
    "$INFO_PLIST_SOURCE"
    "$PYTHON_SCRIPT_SOURCE"
)

for required in "${required_files[@]}"; do
    if [[ ! -e "$required" ]]; then
        printf 'Falta un recurso obligatorio: %s\n' "$required" >&2
        exit 1
    fi
done

/usr/bin/plutil -lint "$INFO_PLIST_SOURCE" >/dev/null
/usr/bin/python3 -m py_compile "$PYTHON_SCRIPT_SOURCE"

swift build -c release --product InpaintVideosApp

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    printf 'No se encontro el ejecutable Release en: %s\n' "$EXECUTABLE_PATH" >&2
    exit 1
fi

architectures="$(/usr/bin/lipo -archs "$EXECUTABLE_PATH")"
case " $architectures " in
    *" arm64 "*) ;;
    *)
        printf 'El ejecutable no contiene arquitectura arm64: %s\n' "$architectures" >&2
        exit 1
        ;;
esac

/bin/rm -rf "$DIST_DIR"
/bin/mkdir -p \
    "$STAGING_APP/Contents/MacOS" \
    "$STAGING_APP/Contents/Resources/Scripts" \
    "$DMG_STAGE_DIR" \
    "$DIST_DIR" \
    "$VERIFY_MOUNT"

/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$INFO_PLIST_SOURCE" "$STAGING_APP/Contents/Info.plist"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$EXECUTABLE_PATH" "$STAGING_APP/Contents/MacOS/InpaintVideosApp"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$PYTHON_SCRIPT_SOURCE" "$STAGING_APP/Contents/Resources/Scripts/watermark_pipeline.py"

/usr/bin/find "$STAGING_APP" -type d -exec /bin/chmod 755 {} +
/usr/bin/find "$STAGING_APP" -type f -exec /bin/chmod 644 {} +
/bin/chmod 755 \
    "$STAGING_APP/Contents/MacOS/InpaintVideosApp" \
    "$STAGING_APP/Contents/Resources/Scripts/watermark_pipeline.py"

/usr/bin/xattr -cr "$STAGING_APP"
/usr/bin/xattr -dr com.apple.quarantine "$STAGING_APP" 2>/dev/null || true

SIGNING_IDENTITY_VALUE="$(resolve_signing_identity)"
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY_VALUE" "$STAGING_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$STAGING_APP" "$DMG_STAGE_DIR/$APP_NAME"
/bin/ln -s /Applications "$DMG_STAGE_DIR/Applications"

/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "Inpaint Videos" \
    -srcfolder "$DMG_STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$VERIFY_MOUNT" "$DMG_PATH" >/dev/null
/usr/bin/codesign --verify --deep --strict --verbose=2 "$VERIFY_MOUNT/$APP_NAME"
/usr/bin/hdiutil detach "$VERIFY_MOUNT" >/dev/null

printf 'Identidad de firma: %s\n' "$SIGNING_IDENTITY_VALUE"
printf 'Aplicacion de staging: %s\n' "$STAGING_APP"
printf 'DMG: %s\n' "$DMG_PATH"
printf 'Arquitecturas: %s\n' "$architectures"
