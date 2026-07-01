import CoreGraphics
import Foundation

struct WatermarkDetectionResult {
    let normalizedRect: CGRect
    let normalizedRegions: [CGRect]
    let confidence: Double
}

struct VideoProcessor {
    private let pythonEngine = PythonVideoEngine()

    func detectWatermark(inputURL: URL) async throws -> WatermarkDetectionResult {
        try pythonEngine.detectWatermark(inputURL: inputURL)
    }

    func cleanVideo(
        inputURL: URL,
        outputURL: URL,
        manualRect: CGRect?,
        useAutomaticDetection: Bool
    ) async throws -> WatermarkDetectionResult {
        try pythonEngine.processVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            manualRect: manualRect,
            useAutomaticDetection: useAutomaticDetection
        )
    }
}

private struct PythonVideoEngine {
    func detectWatermark(inputURL: URL) throws -> WatermarkDetectionResult {
        let payload = try runPython(arguments: [
            "detect",
            "--input", inputURL.path,
        ])

        return try payload.asDetectionResult()
    }

    func processVideo(
        inputURL: URL,
        outputURL: URL,
        manualRect: CGRect?,
        useAutomaticDetection: Bool
    ) throws -> WatermarkDetectionResult {
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        var arguments = [
            "process",
            "--input", inputURL.path,
            "--output-video", tempVideoURL.path,
            "--mode", useAutomaticDetection ? "auto" : "manual",
        ]

        if let manualRect {
            arguments += [
                "--rect",
                "\(manualRect.origin.x),\(manualRect.origin.y),\(manualRect.width),\(manualRect.height)",
            ]
        }

        let payload = try runPython(arguments: arguments)
        try muxProcessedVideo(processedVideoURL: tempVideoURL, sourceVideoURL: inputURL, outputURL: outputURL)
        return try payload.asDetectionResult()
    }

    private func muxProcessedVideo(processedVideoURL: URL, sourceVideoURL: URL, outputURL: URL) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        defer {
            try? FileManager.default.removeItem(at: processedVideoURL)
        }

        let result = try ProcessExecutor.run(
            executableURL: try ToolLocator.resolve("ffmpeg"),
            arguments: [
                "-y",
                "-i", processedVideoURL.path,
                "-i", sourceVideoURL.path,
                "-map", "0:v:0",
                "-map", "1:a?",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "18",
                "-c:a", "copy",
                outputURL.path,
            ]
        )

        if result.terminationStatus != 0 {
            let message = String(decoding: result.stderr, as: UTF8.self)
            throw AppError("ffmpeg no pudo recombinar el video procesado.\n\(message)")
        }
    }

    private func runPython(arguments: [String]) throws -> PythonResponsePayload {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        let result = try ProcessExecutor.run(
            executableURL: try resolvePythonInterpreter(),
            arguments: [ProjectPaths.pythonScript.path] + arguments,
            environment: environment
        )

        let output = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.terminationStatus == 0 else {
            if let payload = try? JSONDecoder().decode(PythonResponsePayload.self, from: Data(output.utf8)) {
                throw AppError(payload.message ?? "El pipeline Python ha fallado.")
            }

            throw AppError("El pipeline Python ha fallado.\n\(error.isEmpty ? output : error)")
        }

        guard let data = output.data(using: .utf8) else {
            throw AppError("La salida del pipeline Python no es valida.")
        }

        return try JSONDecoder().decode(PythonResponsePayload.self, from: data)
    }

    private func resolvePythonInterpreter() throws -> URL {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: ProjectPaths.virtualEnvPython.path) {
            return ProjectPaths.virtualEnvPython
        }

        return try ToolLocator.resolve("python3")
    }
}

private struct PythonResponsePayload: Decodable {
    let status: String
    let message: String?
    let rect: PythonRectPayload?
    let regions: [PythonRectPayload]?
    let confidence: Double?

    func asDetectionResult() throws -> WatermarkDetectionResult {
        guard status == "ok", let rect, let confidence else {
            throw AppError(message ?? "No se pudo interpretar la respuesta del detector.")
        }

        return WatermarkDetectionResult(
            normalizedRect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
            normalizedRegions: (regions ?? [rect]).map {
                CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            },
            confidence: confidence
        )
    }
}

private struct PythonRectPayload: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
