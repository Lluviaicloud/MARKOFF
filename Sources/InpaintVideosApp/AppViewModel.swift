import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    enum CleanupMode: String, CaseIterable, Identifiable {
        case automatic
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic:
                return "Auto"
            case .manual:
                return "Manual"
            }
        }
    }

    var inputURL: URL?
    var outputURL: URL?
    var previewImage: NSImage?
    var previewSize: CGSize = .zero
    var watermarkRect: CGRect = CGRect(x: 40, y: 40, width: 160, height: 80)
    var detectedRegions: [CGRect] = []
    var cleanupMode: CleanupMode = .automatic
    var detectionConfidence: Double?
    var isProcessing = false
    var isDetecting = false
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
        detectionConfidence = nil
        detectedRegions = []
        cleanupMode = .automatic

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

        let normalizedRect = WatermarkGeometry.clampedNormalizedRect(for: watermarkRect, canvasSize: previewSize)

        guard cleanupMode == .automatic || (normalizedRect.width > 0.01 && normalizedRect.height > 0.01) else {
            errorMessage = "El area marcada es demasiado pequena."
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = cleanupMode == .automatic
            ? "Detectando e inpaintando la marca automaticamente..."
            : "Inpaintando la zona marcada manualmente..."

        Task {
            do {
                let result = try await processor.cleanVideo(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    manualRect: cleanupMode == .manual ? normalizedRect : nil,
                    useAutomaticDetection: cleanupMode == .automatic
                )
                applyDetection(result)
                isProcessing = false
                statusMessage = "Video limpio exportado en \(outputURL.path)."
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                statusMessage = "La exportacion ha fallado."
            }
        }
    }

    func detectWatermark() {
        guard let inputURL else {
            errorMessage = "Primero selecciona un video de entrada."
            return
        }

        isDetecting = true
        errorMessage = nil
        statusMessage = "Analizando el video para detectar la marca..."

        Task {
            do {
                let result = try await processor.detectWatermark(inputURL: inputURL)
                applyDetection(result)
                cleanupMode = .automatic
                isDetecting = false
                statusMessage = "Marca detectada automaticamente con confianza \(formattedConfidence)."
            } catch {
                isDetecting = false
                detectionConfidence = nil
                detectedRegions = []
                cleanupMode = .manual
                errorMessage = error.localizedDescription
                statusMessage = "La deteccion automatica ha fallado. Puedes ajustar el rectangulo manualmente."
            }
        }
    }

    private func loadPreview(for url: URL) async {
        do {
            let result = try await previewGenerator.generatePreview(for: url)
            previewImage = result.image
            previewSize = result.size
            watermarkRect = WatermarkGeometry.defaultRect(for: result.size)
            detectedRegions = []
            statusMessage = "Vista previa lista. Ejecutando deteccion automatica..."
            detectWatermark()
        } catch {
            previewImage = nil
            previewSize = .zero
            errorMessage = error.localizedDescription
            statusMessage = "No se pudo cargar la vista previa."
        }
    }

    private func applyDetection(_ result: WatermarkDetectionResult) {
        detectionConfidence = result.confidence
        detectedRegions = result.normalizedRegions.map {
            WatermarkGeometry.absoluteRect(normalizedRect: $0, videoSize: previewSize)
        }
        watermarkRect = WatermarkGeometry.absoluteRect(normalizedRect: result.normalizedRect, videoSize: previewSize)
    }

    private var formattedConfidence: String {
        guard let detectionConfidence else {
            return "0%"
        }

        return "\(Int((detectionConfidence * 100).rounded()))%"
    }

    private func defaultOutputURL(for inputURL: URL) -> URL {
        let cleanedName = inputURL.deletingPathExtension().lastPathComponent + "_clean.mp4"
        return inputURL.deletingLastPathComponent().appendingPathComponent(cleanedName)
    }
}
