import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            previewSection
            if viewModel.cleanupMode == .manual {
                manualFields
            }
            bottomBar
        }
        .padding(12)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectInputVideo()
            } label: {
                Label("Abrir", systemImage: "folder")
            }

            Button {
                viewModel.selectOutputLocation()
            } label: {
                Label("Guardar como", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.inputURL == nil)

            Button {
                viewModel.detectWatermark()
            } label: {
                Label(viewModel.isDetecting ? "Detectando…" : "Detectar", systemImage: "wand.and.stars")
            }
            .disabled(viewModel.inputURL == nil || viewModel.previewImage == nil || viewModel.isDetecting || viewModel.isProcessing)

            Button {
                viewModel.runCleanup()
            } label: {
                Label(viewModel.isProcessing ? "Limpiando…" : "Limpiar", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.inputURL == nil || viewModel.previewImage == nil || viewModel.isProcessing || viewModel.isDetecting)

            Spacer()

            Picker("", selection: $viewModel.cleanupMode) {
                ForEach(AppViewModel.CleanupMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .controlSize(.small)
    }

    private var previewSection: some View {
        Group {
            if let previewImage = viewModel.previewImage {
                VideoPreviewCanvas(
                    image: previewImage,
                    imageSize: viewModel.previewSize,
                    rect: $viewModel.watermarkRect,
                    overlayRects: viewModel.cleanupMode == .automatic ? viewModel.detectedRegions : [],
                    isEditable: viewModel.cleanupMode == .manual
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("Abre un video MP4")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var manualFields: some View {
        HStack(spacing: 8) {
            RectField(title: "X", value: $viewModel.watermarkRect.origin.x)
            RectField(title: "Y", value: $viewModel.watermarkRect.origin.y)
            RectField(title: "An", value: $viewModel.watermarkRect.size.width)
            RectField(title: "Al", value: $viewModel.watermarkRect.size.height)
        }
        .controlSize(.small)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isProcessing {
                if let progress = viewModel.cleanupProgress {
                    ProgressView(value: progress) {
                        Text("Limpiando… \(Int((progress * 100).rounded()))%")
                            .font(.caption)
                    }
                } else {
                    ProgressView {
                        Text("Preparando limpieza…")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                }
            }

            HStack(spacing: 8) {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                if let confidence = viewModel.detectionConfidence {
                    Label("\(Int((confidence * 100).rounded()))%", systemImage: "gauge.medium")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption2)
                    .lineLimit(3)
            }
        }
    }
}

private struct RectField: View {
    let title: String
    @Binding var value: CGFloat

    private var numericBinding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = CGFloat($0) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: numericBinding, format: .number.precision(.fractionLength(0...0)))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}
