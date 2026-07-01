import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import MarkOffApp

struct MarkOffAppTests {
    @Test
    func clampRectKeepsSelectionInsideBounds() {
        let rect = CGRect(x: -10, y: 40, width: 500, height: 500)
        let clamped = WatermarkGeometry.clamp(rect, inside: CGSize(width: 320, height: 240))

        #expect(clamped.origin.x == 0)
        #expect(clamped.origin.y == 0)
        #expect(clamped.width == 320)
        #expect(clamped.height == 240)
    }

    @Test
    func normalizedRectProducesExpectedValues() {
        let rect = CGRect(x: 32, y: 24, width: 64, height: 48)
        let normalized = WatermarkGeometry.clampedNormalizedRect(
            for: rect,
            canvasSize: CGSize(width: 320, height: 240)
        )

        #expect(normalized.origin.x == 0.1)
        #expect(normalized.origin.y == 0.1)
        #expect(normalized.width == 0.2)
        #expect(normalized.height == 0.2)
    }

    @Test
    func detectionFailsForNonVideoFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let bogusURL = tempDirectory.appendingPathComponent("bogus.mp4")
        try Data("not a real video".utf8).write(to: bogusURL)

        let processor = VideoProcessor()

        await #expect(throws: Error.self) {
            try await processor.detectWatermark(inputURL: bogusURL)
        }
    }

    @Test
    func automaticDetectionFindsBottomRightWatermark() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        try generateSampleVideo(at: inputURL)

        let detection = try await VideoProcessor().detectWatermark(inputURL: inputURL)

        #expect(detection.confidence > 0.45)
        #expect(detection.normalizedRegions.count >= 2)
        #expect(detection.normalizedRegions.contains(where: { $0.origin.x > 0.55 && $0.origin.y > 0.55 }))
        #expect(detection.normalizedRegions.contains(where: { $0.origin.x > 0.55 && $0.origin.y < 0.20 }))
    }

    @Test
    func automaticDetectionRejectsFalsePositiveCornerOnDarkFrame() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input_no_corner.mp4")
        try generateVideoWithoutCornerWatermark(at: inputURL)

        let detection = try await VideoProcessor().detectWatermark(inputURL: inputURL)

        let hasTopRight = detection.normalizedRegions.contains(where: { $0.origin.x > 0.55 && $0.origin.y < 0.20 })
        let hasBottomRight = detection.normalizedRegions.contains(where: { $0.origin.x > 0.55 && $0.origin.y > 0.55 })

        #expect(hasTopRight)
        #expect(!hasBottomRight)
    }

    @Test
    func automaticCleanupGeneratesOutputVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideo(at: inputURL)

        let processor = VideoProcessor()
        let result = try await processor.cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            manualRect: nil,
            useAutomaticDetection: true
        )

        #expect(result.confidence > 0.45)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? NSNumber ?? 0
        #expect(fileSize.intValue > 0)
    }

    @Test
    func automaticCleanupPreservesVideoDurationWhenAudioIsShorter() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input-with-short-audio.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideoWithShortAudio(at: inputURL)

        _ = try await VideoProcessor().cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            manualRect: nil,
            useAutomaticDetection: true
        )

        let inputDuration = try videoDuration(at: inputURL)
        let outputDuration = try videoDuration(at: outputURL)

        #expect(outputDuration >= inputDuration - 0.05)
    }

    @Test
    func pythonScriptResolutionPrefersBundledResource() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundledScripts = tempDirectory
            .appendingPathComponent("BundleResources", isDirectory: true)
            .appendingPathComponent("Scripts", isDirectory: true)
        let checkoutScripts = tempDirectory
            .appendingPathComponent("CheckoutRoot", isDirectory: true)
            .appendingPathComponent("Scripts", isDirectory: true)

        try FileManager.default.createDirectory(at: bundledScripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkoutScripts, withIntermediateDirectories: true)

        let bundledScript = bundledScripts.appendingPathComponent("watermark_pipeline.py")
        let checkoutScript = checkoutScripts.appendingPathComponent("watermark_pipeline.py")
        try Data("bundled".utf8).write(to: bundledScript)
        try Data("checkout".utf8).write(to: checkoutScript)

        let resolved = ProjectPaths.resolvedPythonScriptURL(
            mainBundleResourceURL: tempDirectory.appendingPathComponent("BundleResources", isDirectory: true),
            projectRootOverride: tempDirectory.appendingPathComponent("CheckoutRoot", isDirectory: true)
        )

        #expect(resolved == bundledScript)
    }

    @Test
    func pythonScriptResolutionFallsBackToCheckoutScript() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkoutScripts = tempDirectory
            .appendingPathComponent("CheckoutRoot", isDirectory: true)
            .appendingPathComponent("Scripts", isDirectory: true)

        try FileManager.default.createDirectory(at: checkoutScripts, withIntermediateDirectories: true)

        let checkoutScript = checkoutScripts.appendingPathComponent("watermark_pipeline.py")
        try Data("checkout".utf8).write(to: checkoutScript)

        let resolved = ProjectPaths.resolvedPythonScriptURL(
            mainBundleResourceURL: tempDirectory.appendingPathComponent("MissingBundle", isDirectory: true),
            projectRootOverride: tempDirectory.appendingPathComponent("CheckoutRoot", isDirectory: true)
        )

        #expect(resolved == checkoutScript)
    }

    @Test
    func automaticCleanupReducesWatermarkBrightness() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideo(at: inputURL)

        let processor = VideoProcessor()
        _ = try await processor.cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            manualRect: nil,
            useAutomaticDetection: true
        )

        let inputFrame = try await firstFrame(from: inputURL)
        let outputFrame = try await firstFrame(from: outputURL)
        let knownWatermarkRect = CGRect(x: 244, y: 184, width: 42, height: 42)
        let inputBottomLuminance = meanLuminance(in: inputFrame, rect: knownWatermarkRect)
        let outputBottomLuminance = meanLuminance(in: outputFrame, rect: knownWatermarkRect)
        let inputBrightPixels = brightPixelCount(in: inputFrame, rect: knownWatermarkRect, threshold: 240)
        let outputBrightPixels = brightPixelCount(in: outputFrame, rect: knownWatermarkRect, threshold: 240)

        #expect(outputBottomLuminance < inputBottomLuminance * 0.80)
        #expect(Double(outputBrightPixels) < Double(inputBrightPixels) * 0.65)
    }

    @Test
    func cleanupRejectsSameInputAndOutputPath() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sharedURL = tempDirectory.appendingPathComponent("shared.mp4")
        try generateSampleVideo(at: sharedURL)

        let originalAttributes = try FileManager.default.attributesOfItem(atPath: sharedURL.path)
        let originalSize = (originalAttributes[.size] as? NSNumber)?.intValue ?? 0

        let processor = VideoProcessor()
        await #expect(throws: Error.self) {
            _ = try await processor.cleanVideo(
                inputURL: sharedURL,
                outputURL: sharedURL,
                manualRect: nil,
                useAutomaticDetection: true
            )
        }

        let afterAttributes = try FileManager.default.attributesOfItem(atPath: sharedURL.path)
        let afterSize = (afterAttributes[.size] as? NSNumber)?.intValue ?? 0
        #expect(afterSize == originalSize)
        #expect(afterSize > 0)
    }

    @Test
    func cleanupPreservesExistingOutputWhenProcessingFails() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("bogus.mp4")
        let outputURL = tempDirectory.appendingPathComponent("existing.mp4")
        try Data("not a real video".utf8).write(to: inputURL)
        let sentinelPayload = Data("preserved-output-sentinel-bytes".utf8)
        try sentinelPayload.write(to: outputURL)

        let processor = VideoProcessor()
        await #expect(throws: Error.self) {
            _ = try await processor.cleanVideo(
                inputURL: inputURL,
                outputURL: outputURL,
                manualRect: nil,
                useAutomaticDetection: true
            )
        }

        let survived = try Data(contentsOf: outputURL)
        #expect(survived == sentinelPayload)
    }

    @Test
    func manualCleanupOverwritesExistingOutput() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideo(at: inputURL)
        try Data("old".utf8).write(to: outputURL)

        let processor = VideoProcessor()
        _ = try await processor.cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            manualRect: CGRect(x: 0.68, y: 0.68, width: 0.22, height: 0.18),
            useAutomaticDetection: false
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? NSNumber ?? 0
        #expect(fileSize.intValue > 3)
    }

    private func generateSampleVideo(at url: URL) throws {
        let ffmpegURL = try ToolLocator.resolve("ffmpeg")
        let result = try ProcessExecutor.run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-f", "lavfi",
                "-i", "color=c=black:s=320x240:d=1",
                "-vf", "drawbox=x='20+mod(t*120,140)':y=34:w=72:h=72:color=gray@1:t=fill,drawbox=x=116:y='70+mod(t*80,86)':w=36:h=36:color=blue@1:t=fill,drawbox=x=244:y=184:w=42:h=42:color=white@1:t=fill,drawbox=x=178:y=34:w=28:h=28:color=white@1:t=fill,drawbox=x=214:y=40:w=74:h=7:color=white@1:t=fill,drawbox=x=214:y=54:w=92:h=7:color=white@1:t=fill",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                url.path,
            ]
        )

        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw AppError("No se pudo generar el video de prueba.\n\(message)")
        }
    }

    private func generateVideoWithoutCornerWatermark(at url: URL) throws {
        let ffmpegURL = try ToolLocator.resolve("ffmpeg")
        let result = try ProcessExecutor.run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-f", "lavfi",
                "-i", "color=c=black:s=320x240:d=1",
                "-vf", "drawbox=x='20+mod(t*120,140)':y=34:w=72:h=72:color=gray@1:t=fill,drawbox=x=116:y='70+mod(t*80,86)':w=36:h=36:color=blue@1:t=fill,drawbox=x=178:y=34:w=28:h=28:color=white@1:t=fill,drawbox=x=214:y=40:w=74:h=7:color=white@1:t=fill,drawbox=x=214:y=54:w=92:h=7:color=white@1:t=fill",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                url.path,
            ]
        )

        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw AppError("No se pudo generar el video de prueba sin marca de esquina.\n\(message)")
        }
    }

    private func generateSampleVideoWithShortAudio(at url: URL) throws {
        let ffmpegURL = try ToolLocator.resolve("ffmpeg")
        let result = try ProcessExecutor.run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-f", "lavfi",
                "-i", "color=c=black:s=320x240:d=1",
                "-f", "lavfi",
                "-i", "sine=frequency=660:duration=0.55",
                "-vf", "drawbox=x=244:y=184:w=42:h=42:color=white@1:t=fill",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-shortest",
                url.path,
            ]
        )

        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw AppError("No se pudo generar el video de prueba con audio corto.\n\(message)")
        }
    }

    private func firstFrame(from url: URL) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: AppError("No se pudo generar el frame de prueba."))
            }
        }
    }

    private func absoluteRect(from normalizedRect: CGRect, in image: CGImage) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * CGFloat(image.width),
            y: normalizedRect.origin.y * CGFloat(image.height),
            width: normalizedRect.width * CGFloat(image.width),
            height: normalizedRect.height * CGFloat(image.height)
        )
    }

    private func meanLuminance(in image: CGImage, rect: CGRect) -> Double {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }

        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let startX = max(0, Int(rect.minX.rounded(.down)))
        let endX = min(image.width, Int(rect.maxX.rounded(.up)))
        let startY = max(0, Int(rect.minY.rounded(.down)))
        let endY = min(image.height, Int(rect.maxY.rounded(.up)))

        var total = 0.0
        var count = 0

        for y in startY..<endY {
            for x in startX..<endX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let blue = Double(bytes[offset + 2])
                total += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                count += 1
            }
        }

        return count > 0 ? total / Double(count) : 0
    }

    private func brightPixelCount(in image: CGImage, rect: CGRect, threshold: UInt8) -> Int {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }

        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let startX = max(0, Int(rect.minX.rounded(.down)))
        let endX = min(image.width, Int(rect.maxX.rounded(.up)))
        let startY = max(0, Int(rect.minY.rounded(.down)))
        let endY = min(image.height, Int(rect.maxY.rounded(.up)))

        var total = 0
        for y in startY..<endY {
            for x in startX..<endX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = bytes[offset]
                let green = bytes[offset + 1]
                let blue = bytes[offset + 2]
                if red >= threshold && green >= threshold && blue >= threshold {
                    total += 1
                }
            }
        }

        return total
    }

    private func videoDuration(at url: URL) throws -> Double {
        let ffprobeURL = try ToolLocator.resolve("ffprobe")
        let result = try ProcessExecutor.run(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path,
            ]
        )

        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw AppError("No se pudo medir la duracion del video.\n\(message)")
        }

        let value = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let duration = Double(value) else {
            throw AppError("La duracion reportada no es valida.")
        }

        return duration
    }
}
