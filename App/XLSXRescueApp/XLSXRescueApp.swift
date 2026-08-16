import SwiftUI

@main
struct XLSXRescueApp: App {
    @State private var model = RecoveryViewModel(runner: AppRecoveryRunner())

    var body: some Scene {
        WindowGroup("XLSX Rescue") {
            RecoveryDashboardView(model: model)
                .frame(minWidth: 860, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Encrypted Workbook…") {
                    if let url = FileSelectionService.chooseWorkbook() {
                        model.selectInput(.workbook(url))
                    }
                }
                .keyboardShortcut("o")
                Button("Reset Recovery") { model.reset() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Recovery") {
                Button("Start") { model.start() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("Pause") { model.pause() }
                Button("Resume") { model.resume() }
                Divider()
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
