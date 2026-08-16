import SwiftUI

@main
struct XLSXRescueApp: App {
    @State private var model = RecoveryViewModel()

    var body: some Scene {
        WindowGroup("XLSX Rescue") {
            RecoveryDashboardView(model: model)
                .frame(minWidth: 780, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}
