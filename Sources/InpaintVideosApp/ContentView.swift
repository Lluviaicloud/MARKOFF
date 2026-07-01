import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            controls
            previewSection
            footer
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limpieza local de marcas de agua")
                .font(.largeTitle.weight(.semibold))
            Text("MVP de fase 1: seleccion manual del area y regeneracion con ffmpeg sobre videos MP4.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Seleccionar MP4") {
                viewModel.selectInputVideo()
            }

            Button("Guardar Como") {
                viewModel.selectOutputLocation()
            }
            .disabled(viewModel.inputURL == nil)

            Button(viewModel.isProcessing ? "Procesando..." : "Limpiar Video") {
                viewModel.runCleanup()
            }
            .disabled(viewModel.inputURL == nil || viewModel.previewImage == nil || viewModel.isProcessing)

            Spacer()
        }
    }

    private var previewSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vista previa")
                    .font(.headline)

                if let previewImage = viewModel.previewImage {
                    VideoPreviewCanvas(
                        image: previewImage,
                        imageSize: viewModel.previewSize,
                        rect: $viewModel.watermarkRect
                    )
                    .frame(maxWidth: 760, maxHeight: 520)
                    .background(Color.black.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                        .overlay {
                            Text("Sin vista previa")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 760, height: 520)
                }
            }

            inspector
                .frame(width: 260)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Inspector")
                .font(.headline)

            LabeledContent("Entrada") {
                Text(viewModel.inputURL?.lastPathComponent ?? "No seleccionado")
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Salida") {
                Text(viewModel.outputURL?.lastPathComponent ?? "No definida")
                    .multilineTextAlignment(.trailing)
            }

            Divider()

            RectField(title: "X", value: $viewModel.watermarkRect.origin.x)
            RectField(title: "Y", value: $viewModel.watermarkRect.origin.y)
            RectField(title: "Ancho", value: $viewModel.watermarkRect.size.width)
            RectField(title: "Alto", value: $viewModel.watermarkRect.size.height)

            Divider()

            Text("La marca debe quedar totalmente contenida dentro del rectangulo rojo.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.statusMessage)
                .font(.subheadline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
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
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: numericBinding, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 110)
                .textFieldStyle(.roundedBorder)
        }
    }
}
