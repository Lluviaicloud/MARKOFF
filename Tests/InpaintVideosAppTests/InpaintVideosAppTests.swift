import CoreGraphics
import Foundation
import Testing
@testable import InpaintVideosApp

struct InpaintVideosAppTests {
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
    func ffprobeFailsForNonVideoFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let bogusURL = tempDirectory.appendingPathComponent("bogus.mp4")
        try Data("not a real video".utf8).write(to: bogusURL)

        let processor = VideoProcessor()

        await #expect(throws: Error.self) {
            try await processor.cleanVideo(
                inputURL: bogusURL,
                outputURL: tempDirectory.appendingPathComponent("out.mp4"),
                normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
            )
        }
    }

    @Test
    func cleanupGeneratesOutputVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideo(at: inputURL)

        let processor = VideoProcessor()
        try await processor.cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            normalizedRect: CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.15)
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? NSNumber ?? 0
        #expect(fileSize.intValue > 0)
    }

    @Test
    func cleanupOverwritesExistingOutput() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mp4")
        let outputURL = tempDirectory.appendingPathComponent("output.mp4")

        try generateSampleVideo(at: inputURL)
        try Data("old".utf8).write(to: outputURL)

        let processor = VideoProcessor()
        try await processor.cleanVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            normalizedRect: CGRect(x: 0.68, y: 0.68, width: 0.22, height: 0.18)
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? NSNumber ?? 0
        #expect(fileSize.intValue > 3)
    }

    private func generateSampleVideo(at url: URL) throws {
        let ffmpegURL = try ToolLocator.resolve("ffmpeg")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-f", "lavfi",
            "-i", "color=c=black:s=320x240:d=1",
            "-vf", "drawbox=x=220:y=170:w=70:h=35:color=white:t=fill",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            url.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
            throw AppError("No se pudo generar el video de prueba.\n\(message)")
        }
    }
}
