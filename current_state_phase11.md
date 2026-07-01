# Current State Phase 11

- Phase 11 closing date and status: 2026-07-01, IMPLEMENTED (uncommitted; user to commit)
- Phase 11 scope: renombrado del producto a **MarkOff**

## Esquema de nombres adoptado

| Aspecto | Antes | Ahora |
|---------|-------|-------|
| Nombre visible (CFBundleName/DisplayName, titulo de ventana, volname DMG) | Inpaint Videos | MarkOff |
| Target / producto / modulo SwiftPM | InpaintVideosApp | MarkOffApp |
| Test target | InpaintVideosAppTests | MarkOffAppTests |
| @main struct | InpaintVideosApp | MarkOffApp |
| Bundle identifier | com.luispelaez.inpaintvideos | com.luispelaez.markoff |
| App bundle | InpaintVideos.app | MarkOff.app |
| Artefactos | InpaintVideos-macos-arm64.{dmg,pkg} | MarkOff-macos-arm64.{dmg,pkg} |

La carpeta del repositorio (`Inpaint_videos`) se mantiene sin cambios: renombrarla romperia rutas absolutas del `.venv` y de las herramientas, y no formaba parte de la peticion.

## Files Changed

- `Package.swift` / actualizado / package `MarkOff`, producto/target `MarkOffApp`, test target `MarkOffAppTests`, paths a `Sources/MarkOffApp` y `Tests/MarkOffAppTests`
- `Sources/InpaintVideosApp/` → `Sources/MarkOffApp/` / renombrado con `git mv`
- `Tests/InpaintVideosAppTests/` → `Tests/MarkOffAppTests/` / renombrado con `git mv`
- `Tests/MarkOffAppTests/InpaintVideosAppTests.swift` → `MarkOffAppTests.swift` / renombrado; `@testable import MarkOffApp` y `struct MarkOffAppTests`
- `Sources/MarkOffApp/main.swift` / `@main struct MarkOffApp`, `WindowGroup("MarkOff")`
- `Packaging/InpaintVideosApp-Info.plist` → `Packaging/MarkOffApp-Info.plist` / renombrado; DisplayName/Name `MarkOff`, Executable `MarkOffApp`, Identifier `com.luispelaez.markoff`
- `Scripts/build_release_bundle.sh` / tokens a MarkOff + **fix**: ya no borra todo `dist/`, solo su propio DMG, para no destruir el `.pkg`
- `Scripts/build_pkg_installer.sh` / tokens a MarkOff (APP_NAME, PKG_PATH, BUNDLE_IDENTIFIER, ejecutable, plist)
- `README.md` / titulo `# MarkOff`, comando `swift run MarkOffApp`, rutas de artefactos

## Verification

- Grep de residuos `InpaintVideos`/`Inpaint Videos`/`inpaintvideos` en swift/plist/sh/md (excluyendo docs historicos, audit, `.build`, `.venv`, `.git`): **ninguno**
- `python3 -m py_compile Scripts/watermark_pipeline.py`: OK
- `swift test --scratch-path /private/tmp/markoff-build`: **13/13** verde, suite reportada como `MarkOffAppTests`
- `Scripts/build_pkg_installer.sh`: genera `dist/MarkOff-macos-arm64.pkg`, payload contiene `MarkOff.app`, identificador `com.luispelaez.markoff`
- `Scripts/build_release_bundle.sh`: genera `dist/MarkOff-macos-arm64.dmg`, montado y verificado con `codesign --verify --deep --strict`
- Ambos artefactos conviven en `dist/` tras el fix del wipe
- Verificacion del `.app` dentro del `.pkg`: `CFBundleDisplayName=MarkOff`, `CFBundleExecutable=MarkOffApp` (binario `Contents/MacOS/MarkOffApp`), `CFBundleIdentifier=com.luispelaez.markoff`, firma valida

## Bug corregido de paso

- `build_release_bundle.sh` hacia `rm -rf dist/` al inicio (heredado de fase 5, cuando solo existia el DMG). Con dos artefactos esto significaba que generar el DMG borraba el `.pkg` (y viceversa el pkg ya era conservador desde fase 10). Ahora ambos scripts solo eliminan su propio artefacto antes de recrearlo.

## Known Limitations

- La carpeta del repo sigue llamandose `Inpaint_videos`; solo cambio el nombre del producto/artefactos, no la ruta del proyecto
- Los documentos historicos de fases 1-10 conservan el nombre antiguo a proposito (son registro de lo que se hizo entonces)
- Persisten las limitaciones funcionales previas (estrella fija de esquina sin resolver, dependencia de herramientas del sistema, double-encode, VFR)

## Rollback Instructions

1. `git status` para revisar los renombrados (git los muestra como renames) y las ediciones
2. `git reset --hard` al commit anterior una vez la fase quede committed revierte todo el renombrado de golpe
3. Eliminar artefactos si se desea: `rm -f dist/MarkOff-macos-arm64.dmg dist/MarkOff-macos-arm64.pkg`

## Next Phase Entry Conditions

- Si se quiere el icono/branding alineado con "MarkOff", regenerar `AppIcon.icns` desde un master acorde al nuevo nombre
- Retomar las features pendientes (marcas fijas manuales para la estrella de esquina; paquete autocontenido)
