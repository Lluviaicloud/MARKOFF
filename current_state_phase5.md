# Current State Phase 5

- Phase 5 closing commit date and status: 2026-07-01 14:50 CEST, COMMITTED
- Phase 5 closing commit reference: `492f609` (`Phase 5: harden macOS packaging pipeline`)
- Phase 5 scope: hardening of the macOS packaging pipeline for the v1.0 internal distribution build

## What Was Built

- Robust `.dmg` packaging flow for `InpaintVideosApp` using a temporary staging area outside `Documents`
- Clean bundle assembly with `ditto` flags that strip extended attributes and quarantine metadata during packaging
- Automatic signing with the locally available Apple code-signing identity
- Real post-build verification of the `.app` mounted from the generated `.dmg`
- Runtime script path resolution aligned with standard app-bundle resources under `Contents/Resources/Scripts`

## Files Changed

- `.gitignore` / updated / ignored `.swiftpm` generated package metadata and preserved build artifact ignores
- `Packaging/InpaintVideosApp-Info.plist` / created / bundle metadata for the packaged macOS app
- `README.md` / updated / documented v1.0 packaging output and current packaging model
- `Scripts/build_release_bundle.sh` / created and hardened / release packager with validation, signing, DMG creation, and mounted verification
- `Sources/InpaintVideosApp/ProjectPaths.swift` / updated / resolves the Python script from app resources before checkout fallback
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / updated / added path-resolution regression tests for bundled vs checkout script lookup

## Strategy Applied

- Reused the proven packaging pattern from the user's `AutoMasterApp` flow instead of introducing a new release architecture
- Kept the app structure minimal: executable plus bundled Python script resource
- Signed the staged app with the locally available `Apple Development` identity because no `Developer ID Application` certificate is installed on this Mac
- Verified the actual deliverable by mounting the generated `.dmg` and checking the embedded app with `codesign --verify --deep --strict`

## Adversarial Audit Findings

- Red:
- The first packaging iteration copied bundle contents in a way that let `Documents` and File Provider metadata contaminate the app bundle and invalidate strict code-sign verification.
- Evidence: earlier strict verification reported `resource fork, Finder information, or similar detritus not allowed`.
- Fix applied: temporary staging moved to `/private/tmp` and all bundle copies changed to `ditto --norsrc --noextattr --noqtn --noacl`, followed by mounted verification of the app inside the generated `.dmg`.

- Yellow:
- The first hardened script accidentally validated a Python file with `/bin/bash -n`.
- Evidence: build failed on `watermark_pipeline.py` with `syntax error near unexpected token '('`.
- Fix applied: syntax validation changed to `/usr/bin/python3 -m py_compile`.

- Yellow:
- Resource lookup for the Python pipeline originally depended on SwiftPM's generated `Bundle.module` assumptions and checkout fallback.
- Risk: manual `.app` assembly could drift from that structure.
- Fix applied: runtime now prefers `Bundle.main.resourceURL/Scripts/watermark_pipeline.py`, which matches the packaged app layout directly.

## Re-Audit Results

- `swift test --scratch-path /private/tmp/inpaint-videos-build` passed `10/10`
- `./Scripts/build_release_bundle.sh` completed successfully
- Strict verification on staged app passed:
- `/private/tmp/inpaint-videos-release.../InpaintVideos.app: valid on disk`
- Strict verification on mounted app from the generated `.dmg` passed:
- `/private/tmp/inpaint-videos-release.../verify-mount/InpaintVideos.app: valid on disk`
- Packaging output produced:
- `~/Documents/Inpaint_videos/dist/InpaintVideos-macos-arm64.dmg`
- Signing identity used:
- `Apple Development: <redacted-email> (<redacted-team-id>)`
- Architecture verified:
- `arm64`

## Known Limitations

- This is still an internal/local distribution build, not a public macOS release
- Gatekeeper notarization is not configured because this Mac does not currently expose a `Developer ID Application` certificate or `notarytool` credentials
- The packaged app still depends on external `python3`, `ffmpeg`, and `ffprobe` being available on the destination machine

## Rollback Instructions

1. Run `git status` and confirm there is no uncommitted work you need to preserve.
2. Run `git reset --hard HEAD~2` to remove both the phase-5 implementation commit and the phase-state sync commit.
3. Delete the generated packaging artifact if still present:
   `rm -rf ~/Documents/Inpaint_videos/dist`

## Next Phase Entry Conditions

- Decide whether v2.0 should bundle `python3` and media tools or continue relying on host-installed dependencies
- If external distribution is required, install a `Developer ID Application` certificate and configure `notarytool`
- If audio preservation becomes part of scope, move to the planned extract-audio, process-video, and reattach-audio pipeline
