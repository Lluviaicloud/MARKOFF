import SwiftUI

@main
struct InpaintVideosApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("Inpaint Videos") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowResizability(.contentSize)
    }
}
