import Foundation

struct ProcessExecutionResult {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
}

enum ProcessExecutor {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> ProcessExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let tempDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent(UUID().uuidString)
        let stderrURL = tempDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        try stdoutHandle.close()
        try stderrHandle.close()

        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)

        try? FileManager.default.removeItem(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)

        return ProcessExecutionResult(
            stdout: stdoutData,
            stderr: stderrData,
            terminationStatus: process.terminationStatus
        )
    }
}
