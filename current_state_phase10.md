# Current State Phase 10

- Phase 10 closing date and status: 2026-07-01, IMPLEMENTED (uncommitted; user to commit)
- Phase 10 scope: instalador `.pkg` que instala `InpaintVideos.app` en `/Applications`

## Decision de alcance (confirmada por el usuario)

Se pregunto explicitamente el alcance del `.pkg` entre tres opciones (instalador simple, app + Python incluido, autocontenido total). El usuario eligio **"Instalador de la app (fiable)"**: el paquete instala la app y sigue dependiendo de `python3`/`ffmpeg`/`ffprobe` presentes en el equipo destino, igual que el `.dmg` actual.

## What Was Built

- Script `Scripts/build_pkg_installer.sh` que produce `dist/InpaintVideos-macos-arm64.pkg`
- El `.pkg` instala `InpaintVideos.app` en `/Applications` mediante `pkgbuild --install-location /Applications`
- README actualizado con la seccion de generacion del instalador y sus limitaciones

## Files Changed

- `Scripts/build_pkg_installer.sh` / creado / empaquetador `.pkg`: build release, staging endurecido, firma del `.app`, `pkgbuild`, y verificacion del payload
- `README.md` / actualizado / seccion "Generar instalador .pkg" con notas de dependencias y firma

## Strategy Applied

- Se reutilizo el patron de staging endurecido del `.dmg` (staging en `/private/tmp` fuera de `Documents`, copias con `ditto --norsrc --noextattr --noqtn --noacl`, `xattr -cr`, firma con la identidad `Apple Development` local) para que la app quede con firma estricta valida
- Sobre ese `.app` firmado se ejecuta `pkgbuild --root <pkg-root> --install-location /Applications`, donde `pkg-root` contiene solo `InpaintVideos.app`
- El script es conservador con `dist/`: ya no borra toda la carpeta (para no destruir un `.dmg` previo), solo elimina el `.pkg` anterior
- No se firma el `.pkg` con `Developer ID Installer` porque no existe ese certificado en el equipo; el paquete queda sin firma de instalador (la app interior si esta firmada)

## Verification

- `Scripts/build_pkg_installer.sh` completo con exito:
  - `swift build -c release` OK, arquitectura `arm64` verificada
  - `codesign --verify --deep --strict` sobre el `.app` de staging: valido
  - `pkgbuild` escribio `dist/InpaintVideos-macos-arm64.pkg` (~747 KB)
  - `pkgutil --payload-files` confirma que el payload contiene `InpaintVideos.app`
- Verificacion adversarial del deliverable:
  - Se expandio el `.pkg` con `pkgutil --expand-full` y se localizo el `Payload/InpaintVideos.app`
  - `codesign --verify --deep --strict --verbose=2` sobre la app extraida: `valid on disk` + `satisfies its Designated Requirement`, exit 0
  - El arbol extraido de la app tiene **0** archivos AppleDouble `._` reales; los `._` que lista `pkgutil --payload-files` son solo sidecars de xattr del cpio, reensamblados al instalar
- La app depende de `python3`/`ffmpeg`/`ffprobe` del sistema; el `.venv` local (166 MB, no relocalizable) y los binarios de Homebrew (ffmpeg enlaza 18 dylibs) NO se incluyen, por decision de alcance

## Known Limitations

- El `.pkg` no es autocontenido: en un Mac sin `python3`/`ffmpeg`/`ffprobe` la app se instala pero fallara al procesar. Un paquete autocontenido seria una fase futura (bundlear Python/OpenCV + ffmpeg y sus dylibs)
- El `.pkg` no esta notarizado ni firmado como instalador (`Developer ID Installer` ausente); en otros Macs Gatekeeper puede pedir clic derecho > Abrir o instalar via `sudo installer -pkg ... -target /`
- Persisten las limitaciones funcionales previas (estrella fija de esquina sin resolver, double-encode, VFR)

## Rollback Instructions

1. `git status` para confirmar los archivos de fase 10 (`Scripts/build_pkg_installer.sh`, `README.md`, este documento)
2. Eliminar el artefacto si se desea: `rm -f dist/InpaintVideos-macos-arm64.pkg`
3. Revertir manualmente el script y el README o `git reset --hard` al commit anterior una vez la fase quede committed

## Next Phase Entry Conditions

- Si en el futuro se requiere distribucion a Macs limpios, evaluar la opcion autocontenida: reconstruir un Python relocalizable (p. ej. python-build-standalone) con OpenCV/numpy, incluir binarios estaticos de `ffmpeg`/`ffprobe`, ajustar `ToolLocator`/`ProjectPaths` para preferir binarios del bundle, y firmar cada binario
- Si se requiere instalacion sin avisos de Gatekeeper, obtener un certificado `Developer ID Installer` + `Developer ID Application` y configurar notarizacion con `notarytool`
