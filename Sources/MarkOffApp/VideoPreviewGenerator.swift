import AVFoundation
import AppKit
import Foundation

struct VideoPreview {
    let image: NSImage
    let size: CGSize
}

struct VideoPreviewGenerator {
    func generatePreview(for url: URL) async throws -> VideoPreview {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw AppError("El archivo no contiene una pista de video.")
        }

        let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
        let absoluteSize = CGSize(width: abs(size.width), height: abs(size.height))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let cgImage = try await generateImage(generator: generator)
        let image = NSImage(cgImage: cgImage, size: absoluteSize)
        return VideoPreview(image: image, size: absoluteSize)
    }

    private func generateImage(generator: AVAssetImageGenerator) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: AppError("No se pudo generar el frame de vista previa."))
            }
        }
    }
}
