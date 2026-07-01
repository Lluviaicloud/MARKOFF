import Foundation

struct VideoProcessor {
    func cleanVideo(inputURL: URL, outputURL: URL, normalizedRect: CGRect) async throws {
        let probe = try runFFprobe(for: inputURL)
        let rect = WatermarkGeometry.absoluteRect(
            normalizedRect: normalizedRect,
            videoSize: probe.size
        )

        let filter = "delogo=x=\(Int(rect.origin.x.rounded())):y=\(Int(rect.origin.y.rounded())):w=\(max(1, Int(rect.width.rounded()))):h=\(max(1, Int(rect.height.rounded()))):show=0"

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = try ToolLocator.resolve("ffmpeg")
        process.arguments = [
            "-y",
            "-i", inputURL.path,
            "-vf", filter,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "18",
            "-c:a", "copy",
            outputURL.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
            throw AppError("ffmpeg fallo al procesar el video.\n\(message)")
        }
    }

    private func runFFprobe(for inputURL: URL) throws -> VideoProbe {
        let process = Process()
        process.executableURL = try ToolLocator.resolve("ffprobe")
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x",
            inputURL.path,
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
            throw AppError("ffprobe no pudo leer el video.\n\(message)")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else {
            throw AppError("No se pudo interpretar la resolucion del video.")
        }

        return VideoProbe(size: CGSize(width: width, height: height))
    }
}

private struct VideoProbe {
    let size: CGSize
}
