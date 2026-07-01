import Foundation

enum ToolLocator {
    static func resolve(_ toolName: String) throws -> URL {
        let fm = FileManager.default
        let directCandidates = [
            "/opt/homebrew/bin/\(toolName)",
            "/usr/local/bin/\(toolName)",
            "/usr/bin/\(toolName)",
        ]

        for candidate in directCandidates where fm.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in path.split(separator: ":") {
            let candidate = String(entry) + "/" + toolName
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw AppError("No se encontro la herramienta '\(toolName)' en el sistema.")
    }
}
