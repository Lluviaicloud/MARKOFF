# Current State Phase 2

- Phase 2 closing commit date and status: 2026-07-01 13:33:17 CEST, READY TO COMMIT

## What Was Built

- Automatic watermark detection pipeline using Python and OpenCV over sampled video frames
- Real per-frame inpainting pipeline using `cv2.inpaint` with automatic or manual mask guidance
- Swift bridge from the macOS app to the Python engine, preserving the existing native SwiftUI workflow
- UI controls for automatic detection, confidence display, and selection of automatic or manual cleanup mode
- Expanded automated validation suite for detection, processing, overwrite behavior, and visible watermark reduction

## Files Changed

- `.gitignore` / updated / ignored local virtualenv, build outputs, and generated cleaned videos
- `Package.swift` / updated / copied the `Scripts` directory into test resources
- `README.md` / updated / documented phase-2 capabilities and Python dependencies
- `Scripts/watermark_pipeline.py` / created / automatic detection and OpenCV inpainting engine
- `Sources/InpaintVideosApp/ProjectPaths.swift` / created / project-root and script path resolution
- `Sources/InpaintVideosApp/PythonVideoEngine.swift` / created / Swift bridge to the Python detection and inpainting pipeline
- `Sources/InpaintVideosApp/AppViewModel.swift` / updated / automatic detection flow, confidence state, and cleanup mode selection
- `Sources/InpaintVideosApp/ContentView.swift` / updated / autodetect action, mode picker, and confidence display
- `Sources/InpaintVideosApp/VideoProcessor.swift` / deleted / replaced by the Python-backed processing engine
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / updated / phase-2 audit scenarios

## Strategy Applied

- Kept the macOS app native in SwiftUI and moved advanced video analysis into a Python/OpenCV engine to avoid native OpenCV bindings in this phase
- Used sampled-frame heuristics for automatic detection because no trained watermark model or labeled dataset existed in the project state
- Preserved a manual fallback path because heuristic detection can fail on videos whose watermark style differs from the sampled evidence
- Reused `ffmpeg` only for final muxing so the original audio track remains intact after inpainting

## Audit Results

- Step 4 scenarios executed: 7
- `swift build` completed successfully after bridge-integration fixes
- `swift test` passed with 7 scenarios:
- geometry clamp inside bounds
- normalized coordinate conversion
- invalid non-video detection failure
- automatic detection of a bottom-right watermark
- automatic cleanup output generation
- manual cleanup overwrite behavior
- visible bright-pixel reduction after inpainting on a synthetic watermark
- Real evidence check on `/Users/luispelaez/Desktop/video luna.MP4`:
- automatic detection converged to the lower-right watermark region with confidence `0.771`
- processed sample output was generated at `/Users/luispelaez/Documents/Inpaint_videos/video_luna_clean_phase2.mp4`

## Step 5 Fixes

- Corrected Python bridge error propagation in Swift
- Tuned the detector with stronger border and lower-frame priors based on the real sample video
- Expanded the automatic mask padding and effective inpainting area for small bright watermarks
- Replaced an unstable luminance-only audit metric with a bright-pixel reduction check on the synthetic watermark ROI
- Removed deprecated frame extraction in tests by switching to asynchronous AVFoundation image generation

## Known Limitations

- The detector is heuristic, not model-based; unusual watermark positions or low-contrast overlays may require manual adjustment
- The current implementation is optimized for small static marks; animated, moving, or scene-blended overlays may need a future phase
- The Python environment is local to this repository and must exist for the automatic pipeline to run

## Rollback Instructions

1. Run `git status` and confirm only phase-2 files are present.
2. Run `git reset --hard HEAD~1` to drop the phase-2 commit once it exists.
3. If you also want to remove the generated sample output, delete `/Users/luispelaez/Documents/Inpaint_videos/video_luna_clean_phase2.mp4`.

## Next Phase Entry Conditions

- Decide whether phase 3 should package the app as a distributable macOS bundle or keep it as a developer-run tool
- Provide more representative watermark samples if the detector should generalize beyond the current lower-right overlay style
- Decide whether a future phase should replace heuristics with a trained detector or Core ML integration
