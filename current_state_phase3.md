# Current State Phase 3

- Phase 3 closing commit date and status: 2026-07-01 13:53:23 CEST, COMMITTED
- Phase 3 closing commit reference: `94dc71b` (`Phase 3: detect and clean multiple watermark regions`)

## What Was Built

- Automatic multi-region detection for watermark cleanup, including the lower-right overlay and the upper-right Instagram authorship mark
- Swift-side support for multiple detected regions returned by the Python engine
- Preview overlay updates so automatic mode can visualize all detected regions while preserving manual fallback editing
- Real-sample validation against `~/Desktop/video luna.MP4`, specifically targeting the upper-right authorship watermark

## Files Changed

- `Scripts/watermark_pipeline.py` / updated / multi-region detection and tighter top-right mask generation
- `Sources/InpaintVideosApp/PythonVideoEngine.swift` / updated / parsing of multiple detected regions
- `Sources/InpaintVideosApp/AppViewModel.swift` / updated / storage and propagation of detected automatic regions
- `Sources/InpaintVideosApp/ContentView.swift` / updated / UI copy and auto-region preview usage
- `Sources/InpaintVideosApp/VideoPreviewCanvas.swift` / updated / rendering of multiple automatic overlays with manual edit fallback
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / updated / multi-region detection audit scenarios

## Strategy Applied

- Kept the Python/OpenCV engine as the execution core and extended it to return multiple candidate regions instead of only one
- Split detection logic into corner-watermark detection and a dedicated upper-right overlay detector tuned for bright Instagram-style authorship marks
- Tightened the upper-right mask to avoid the overbroad cloud smearing observed in the first multi-region attempt
- Preserved manual mode unchanged as the fallback path if the automatic detector misses a watermark

## Audit Results

- Step 4 scenarios executed: 7 automated scenarios plus real visual validation on the user sample video
- `swift test` passed with 7/7 scenarios after the multi-region changes
- Real-sample validation on `~/Desktop/video luna.MP4`:
- automatic detection returned two regions
- lower-right decorative mark: detected
- upper-right Instagram authorship mark: detected
- cleaned output generated at `~/Documents/Inpaint_videos/video_luna_clean_multi_v2.mp4`
- visual check on the first frame confirmed removal of the upper-right authorship watermark without the earlier cloud smear artifact

## Step 5 Fixes

- Reworked the upper-right detector from a coarse merged box to a component-based mask
- Avoided overbroad inpainting by narrowing the selected top-right region and mask morphology
- Extended the Swift bridge and preview rendering to handle multiple automatic regions
- Updated the synthetic audit video so it still exercises multi-region detection logic

## Known Limitations

- The upper-right detector is still heuristic and tuned to bright static authorship marks; low-contrast or animated handles may still require manual cleanup
- The audit for the upper-right case now relies primarily on real-sample visual validation, because synthetic white-text proxies were unstable as a quality metric
- The app continues to depend on the local Python environment in `.venv`

## Rollback Instructions

1. Run `git status` and confirm only phase-3 files are present.
2. Run `git reset --hard HEAD~2` to remove both the phase-3 implementation commit and the phase-state sync commit.
3. Delete `~/Documents/Inpaint_videos/video_luna_clean_multi_v2.mp4` if you also want to remove the generated sample output.

## Next Phase Entry Conditions

- Decide whether to generalize the detector further for additional watermark positions or styles
- Decide whether to package the app as a distributable macOS bundle instead of a developer-run workspace app
- If stronger reconstruction quality is needed, evaluate model-based inpainting or reverse-alpha methods for overlays with known compositing characteristics
