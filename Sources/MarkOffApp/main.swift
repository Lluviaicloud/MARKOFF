import SwiftUI

@main
struct MarkOffApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("MarkOff") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 380, idealWidth: 460, minHeight: 560, idealHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
