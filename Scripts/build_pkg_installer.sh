#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
EXECUTABLE_PATH="$RELEASE_DIR/MarkOffApp"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/MarkOffApp-Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Packaging/AppIcon.icns"
PYTHON_SCRIPT_SOURCE="$ROOT_DIR/Scripts/watermark_pipeline.py"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MarkOff.app"
PKG_PATH="$DIST_DIR/MarkOff-macos-arm64.pkg"
BUNDLE_IDENTIFIER="com.luispelaez.markoff"
PKG_VERSION="1.0"
TEMP_ROOT="$(mktemp -d /private/tmp/inpaint-videos-pkg.XXXXXX)"
STAGING_APP="$TEMP_ROOT/$APP_NAME"
PKG_ROOT="$TEMP_ROOT/pkg-root"

cleanup() {
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
    "$APP_ICON_SOURCE"
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

swift build -c release --product MarkOffApp

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

/bin/mkdir -p \
    "$STAGING_APP/Contents/MacOS" \
    "$STAGING_APP/Contents/Resources/Scripts" \
    "$PKG_ROOT" \
    "$DIST_DIR"

# Ensamblado del bundle con ditto endurecido (sin atributos extendidos que invaliden la firma)
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$INFO_PLIST_SOURCE" "$STAGING_APP/Contents/Info.plist"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$EXECUTABLE_PATH" "$STAGING_APP/Contents/MacOS/MarkOffApp"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$APP_ICON_SOURCE" "$STAGING_APP/Contents/Resources/AppIcon.icns"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$PYTHON_SCRIPT_SOURCE" "$STAGING_APP/Contents/Resources/Scripts/watermark_pipeline.py"

/usr/bin/find "$STAGING_APP" -type d -exec /bin/chmod 755 {} +
/usr/bin/find "$STAGING_APP" -type f -exec /bin/chmod 644 {} +
/bin/chmod 755 \
    "$STAGING_APP/Contents/MacOS/MarkOffApp" \
    "$STAGING_APP/Contents/Resources/Scripts/watermark_pipeline.py"

/usr/bin/xattr -cr "$STAGING_APP"
/usr/bin/xattr -dr com.apple.quarantine "$STAGING_APP" 2>/dev/null || true

SIGNING_IDENTITY_VALUE="$(resolve_signing_identity)"
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY_VALUE" "$STAGING_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

# La raiz del paquete contiene la app firmada; pkgbuild la mapea a /Applications
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
    "$STAGING_APP" "$PKG_ROOT/$APP_NAME"

/bin/rm -f "$PKG_PATH"
/usr/bin/pkgbuild \
    --root "$PKG_ROOT" \
    --install-location /Applications \
    --identifier "$BUNDLE_IDENTIFIER" \
    --version "$PKG_VERSION" \
    "$PKG_PATH"

# Verificacion del paquete generado
/usr/sbin/pkgutil --check-signature "$PKG_PATH" 2>/dev/null || true
/usr/sbin/pkgutil --payload-files "$PKG_PATH" | /usr/bin/grep -q "$APP_NAME" \
    && printf 'Payload contiene %s: OK\n' "$APP_NAME" \
    || { printf 'El payload no contiene %s\n' "$APP_NAME" >&2; exit 1; }

printf 'Identidad de firma de la app: %s\n' "$SIGNING_IDENTITY_VALUE"
printf 'Identificador del paquete: %s\n' "$BUNDLE_IDENTIFIER"
printf 'Version: %s\n' "$PKG_VERSION"
printf 'Aplicacion de staging: %s\n' "$STAGING_APP"
printf 'PKG: %s\n' "$PKG_PATH"
printf 'Arquitecturas: %s\n' "$architectures"
