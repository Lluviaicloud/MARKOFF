import AppKit
import SwiftUI

struct VideoPreviewCanvas: View {
    let image: NSImage
    let imageSize: CGSize
    @Binding var rect: CGRect

    @State private var dragOriginRect: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            let layout = PreviewLayout(containerSize: geometry.size, imageSize: imageSize)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: layout.renderSize.width, height: layout.renderSize.height)
                    .position(x: layout.renderOrigin.x + layout.renderSize.width / 2,
                              y: layout.renderOrigin.y + layout.renderSize.height / 2)

                Rectangle()
                    .path(in: layout.displayRect(for: rect))
                    .stroke(Color.red, lineWidth: 3)

                Rectangle()
                    .fill(Color.red.opacity(0.14))
                    .frame(
                        width: layout.displayRect(for: rect).width,
                        height: layout.displayRect(for: rect).height
                    )
                    .position(
                        x: layout.displayRect(for: rect).midX,
                        y: layout.displayRect(for: rect).midY
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if dragOriginRect == .zero {
                            dragOriginRect = rect
                        }
                        let translated = WatermarkGeometry.translatedRect(
                            dragOriginRect,
                            translation: gesture.translation,
                            scale: layout.scale,
                            bounds: imageSize
                        )
                        rect = translated
                    }
                    .onEnded { _ in
                        dragOriginRect = .zero
                    }
            )
        }
    }
}

private struct PreviewLayout {
    let containerSize: CGSize
    let imageSize: CGSize

    var scale: CGFloat {
        min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    }

    var renderSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    var renderOrigin: CGPoint {
        CGPoint(
            x: (containerSize.width - renderSize.width) / 2,
            y: (containerSize.height - renderSize.height) / 2
        )
    }

    func displayRect(for sourceRect: CGRect) -> CGRect {
        CGRect(
            x: renderOrigin.x + sourceRect.origin.x * scale,
            y: renderOrigin.y + sourceRect.origin.y * scale,
            width: sourceRect.width * scale,
            height: sourceRect.height * scale
        )
    }
}
