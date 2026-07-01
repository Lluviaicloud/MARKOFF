import Foundation

enum ProjectPaths {
    static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static let scriptsDirectory = projectRoot.appendingPathComponent("Scripts", isDirectory: true)
    static let pythonScript: URL = {
        if let bundledScript = Bundle.module.url(
            forResource: "watermark_pipeline",
            withExtension: "py",
            subdirectory: "Scripts"
        ) {
            return bundledScript
        }

        return scriptsDirectory.appendingPathComponent("watermark_pipeline.py")
    }()

    static let virtualEnvPython = projectRoot.appendingPathComponent(".venv/bin/python3")
}
