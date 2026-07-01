import Foundation

enum ProjectPaths {
    static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static let scriptsDirectory = projectRoot.appendingPathComponent("Scripts", isDirectory: true)
    static let pythonScript = resolvedPythonScriptURL()

    static let virtualEnvPython = projectRoot.appendingPathComponent(".venv/bin/python3")

    static func resolvedPythonScriptURL(
        mainBundleResourceURL: URL? = Bundle.main.resourceURL,
        projectRootOverride: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let root = projectRootOverride ?? projectRoot
        let fallbackScript = root
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("watermark_pipeline.py")

        let candidates = [
            mainBundleResourceURL?
                .appendingPathComponent("Scripts", isDirectory: true)
                .appendingPathComponent("watermark_pipeline.py"),
            fallbackScript,
        ].compactMap { $0 }

        for candidate in candidates where fileManager.isReadableFile(atPath: candidate.path) {
            return candidate
        }

        return fallbackScript
    }
}
