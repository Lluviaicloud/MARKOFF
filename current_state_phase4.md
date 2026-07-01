# Current State Phase 4

- Phase 4 closing commit date and status: 2026-07-01 14:20:29 CEST, COMMITTED
- Phase 4 closing commit reference: `7dd5f10` (`Phase 4: harden process execution and preserve duration`)

## What Was Built

- Surgical hardening of the video-processing runtime after an adversarial audit
- Fix for silent truncation of output videos when the source audio track is shorter than the source video track
- Safe process-execution wrapper that avoids pipe-buffer deadlock risk during `ffmpeg` and `python` execution
- Resource-based script resolution for the Python pipeline instead of relying only on source-checkout absolute paths
- Additional automated regression test covering the real truncation failure mode

## Files Changed

- `.gitignore` / updated / ignored Python cache artifacts produced by the processing script
- `Package.swift` / updated / bundled `Scripts` into the executable target resources
- `Sources/InpaintVideosApp/ProcessExecutor.swift` / created / shared safe process runner with captured stdout/stderr
- `Sources/InpaintVideosApp/ProjectPaths.swift` / updated / prefer bundled script resource and fallback to checkout path
- `Sources/InpaintVideosApp/PythonVideoEngine.swift` / updated / removed `-shortest` and switched to the safe process runner
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / updated / added regression coverage for short-audio inputs

## Strategy Applied

- Kept the fixes narrow and local to the runtime boundaries instead of redesigning the video engine
- Removed only the argument responsible for truncating the final muxed output
- Introduced one reusable process-execution abstraction to solve deadlock risk in both the Python bridge and supporting test/process calls
- Bundled the Python script as an app resource so runtime path resolution no longer depends exclusively on source layout

## Adversarial Audit Findings

- Red:
- Output video truncation was real and reproducible.
- Evidence: source sample `~/Desktop/video luna.MP4` had `format.duration=12.000000`; previous cleaned output had `format.duration=10.216009`.
- Root cause: `ffmpeg` mux step used `-shortest`, so the final container was clipped to the shorter audio stream.
- Red:
- `ffmpeg` process execution could deadlock on large stderr output.
- Evidence: in the prior runtime, `Process.waitUntilExit()` was called before draining the `Pipe`.
- Risk: longer or noisier jobs can block when the OS pipe buffer fills.
- Yellow:
- Python script resolution depended on source-tree absolute paths.
- Evidence: the previous `ProjectPaths` implementation built paths from `#filePath`.
- Risk: a relocated or packaged app would fail to find `watermark_pipeline.py`.

## Audit Results

- `swift build` completed successfully after the corrections
- `swift test` passed with 8/8 scenarios
- New regression test passed:
- `automaticCleanupPreservesVideoDurationWhenAudioIsShorter`
- Real evidence check:
- source sample `~/Desktop/video luna.MP4` has `format.duration=12.000000`
- post-fix muxed sample `/private/tmp/video-luna-audit-final.mp4` has `format.duration=12.000000`
- post-fix muxed sample video stream has `duration=12.000000` and `nb_frames=312`
- post-fix muxed sample audio stream remains shorter at `duration=10.216009`, but it no longer truncates the video

## Known Limitations

- The Python runtime still depends on either the local `.venv` or a system `python3` with compatible packages installed
- This phase did not replace the heuristic watermark detector
- The app still uses a double-encode path for processed videos, which is acceptable for now but not ideal for maximum quality preservation

## Rollback Instructions

1. Run `git status` and confirm only phase-4 files are present.
2. Run `git reset --hard HEAD~2` to remove both the phase-4 implementation commit and the phase-state sync commit.
3. If you also want to remove the temporary validation outputs, delete `/private/tmp/video-luna-audit-silent.mp4` and `/private/tmp/video-luna-audit-final.mp4`.

## Next Phase Entry Conditions

- Decide whether to reduce double-encoding by moving to a frame-extraction/reassembly path or a lossless intermediate
- Decide whether the Python dependencies should be bundled or installer-managed for a distributable app
- If packaging remains a goal, validate the bundled resource path and dependency bootstrap in a standalone app bundle
