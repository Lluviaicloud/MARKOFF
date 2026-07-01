import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    var inputURL: URL?
    var outputURL: URL?
    var previewImage: NSImage?
    var previewSize: CGSize = .zero
    var watermarkRect: CGRect = CGRect(x: 40, y: 40, width: 160, height: 80)
    var isProcessing = false
    var statusMessage = "Selecciona un video MP4 para comenzar."
    var errorMessage: String?

    private let previewGenerator = VideoPreviewGenerator()
    private let processor = VideoProcessor()

    func selectInputVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        inputURL = url
        outputURL = defaultOutputURL(for: url)
        errorMessage = nil
        statusMessage = "Generando vista previa..."

        Task {
            await loadPreview(for: url)
        }
    }

    func selectOutputLocation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "video_limpio.mp4"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        outputURL = url.pathExtension.lowercased() == "mp4" ? url : url.appendingPathExtension("mp4")
    }

    func runCleanup() {
        guard let inputURL else {
            errorMessage = "Primero selecciona un video de entrada."
            return
        }

        guard let outputURL else {
            errorMessage = "Define la ruta del video de salida."
            return
        }

        guard previewSize.width > 0, previewSize.height > 0 else {
            errorMessage = "No se pudo calcular la resolución de referencia."
            return
        }

        let normalizedRect = WatermarkGeometry.clampedNormalizedRect(
            for: watermarkRect,
            canvasSize: previewSize
        )

        guard normalizedRect.width > 0.01, normalizedRect.height > 0.01 else {
            errorMessage = "El area marcada es demasiado pequena."
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = "Limpiando video con ffmpeg..."

        Task {
            do {
                try await processor.cleanVideo(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    normalizedRect: normalizedRect
                )
                isProcessing = false
                statusMessage = "Video limpio exportado en \(outputURL.path)."
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                statusMessage = "La exportacion ha fallado."
            }
        }
    }

    private func loadPreview(for url: URL) async {
        do {
            let result = try await previewGenerator.generatePreview(for: url)
            previewImage = result.image
            previewSize = result.size
            watermarkRect = WatermarkGeometry.defaultRect(for: result.size)
            statusMessage = "Ajusta el rectangulo sobre la marca de agua y exporta el video limpio."
        } catch {
            previewImage = nil
            previewSize = .zero
            errorMessage = error.localizedDescription
            statusMessage = "No se pudo cargar la vista previa."
        }
    }

    private func defaultOutputURL(for inputURL: URL) -> URL {
        let cleanedName = inputURL.deletingPathExtension().lastPathComponent + "_clean.mp4"
        return inputURL.deletingLastPathComponent().appendingPathComponent(cleanedName)
    }
}
