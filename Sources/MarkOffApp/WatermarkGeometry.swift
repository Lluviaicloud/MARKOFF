import CoreGraphics
import Foundation

enum WatermarkGeometry {
    static func defaultRect(for size: CGSize) -> CGRect {
        let width = max(120, size.width * 0.18)
        let height = max(60, size.height * 0.12)
        let x = max(16, size.width - width - 32)
        let y = max(16, size.height - height - 32)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func clampedNormalizedRect(for rect: CGRect, canvasSize: CGSize) -> CGRect {
        let clamped = clamp(rect, inside: canvasSize)
        return CGRect(
            x: clamped.origin.x / canvasSize.width,
            y: clamped.origin.y / canvasSize.height,
            width: clamped.width / canvasSize.width,
            height: clamped.height / canvasSize.height
        )
    }

    static func absoluteRect(normalizedRect: CGRect, videoSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * videoSize.width,
            y: normalizedRect.origin.y * videoSize.height,
            width: normalizedRect.width * videoSize.width,
            height: normalizedRect.height * videoSize.height
        )
    }

    static func translatedRect(_ rect: CGRect, translation: CGSize, scale: CGFloat, bounds: CGSize) -> CGRect {
        let translated = CGRect(
            x: rect.origin.x + translation.width / scale,
            y: rect.origin.y + translation.height / scale,
            width: rect.width,
            height: rect.height
        )
        return clamp(translated, inside: bounds)
    }

    static func clamp(_ rect: CGRect, inside bounds: CGSize) -> CGRect {
        let width = min(max(1, rect.width), bounds.width)
        let height = min(max(1, rect.height), bounds.height)
        let x = min(max(0, rect.origin.x), max(0, bounds.width - width))
        let y = min(max(0, rect.origin.y), max(0, bounds.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
