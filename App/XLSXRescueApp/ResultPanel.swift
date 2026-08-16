import AppKit
import SwiftUI

struct ResultPanel: View {
    @Bindable var model: RecoveryViewModel
    @Bindable var clipboard: ClipboardService

    @ViewBuilder var body: some View {
        switch model.state {
        case .recovered(let result): recoveredPanel(result)
        case .decrypting:
            DashboardCard(title: "Saving unencrypted copy", systemImage: "square.and.arrow.down") {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Decrypting and validating the workbook…")
                }
            }
        case .completed(let output): completedPanel(output)
        default: EmptyView()
        }
    }

    private func recoveredPanel(_ result: RecoveryResultSummary) -> some View {
        DashboardCard(title: "Password recovered", systemImage: "checkmark.seal.fill") {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text(model.passwordRevealed ? result.password : String(repeating: "•", count: max(8, min(24, result.password.count))))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityLabel(model.passwordRevealed ? "Recovered password, \(result.password)" : "Recovered password hidden")
                Spacer()
                Toggle("Reveal", isOn: $model.passwordRevealed)
                    .toggleStyle(.switch)
                    .accessibilityHint("Shows or hides the recovered password on screen")
                Button {
                    clipboard.copy(result.password)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c")
            }
            .padding(14)
            .background(.green.opacity(0.09), in: .rect(cornerRadius: 11))

            HStack {
                if clipboard.lastCopiedAt != nil {
                    Label("Copied to clipboard", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Reset", action: model.reset)
                if let source = result.sourceWorkbook {
                    Button("Save Unencrypted Copy…") {
                        if let output = FileSelectionService.chooseExportDestination(source: source) {
                            model.export(to: output)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Select the original workbook to export an unencrypted copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func completedPanel(_ output: URL) -> some View {
        DashboardCard(title: "Unencrypted copy saved", systemImage: "checkmark.circle.fill") {
            Label(output.path(percentEncoded: false), systemImage: "doc.fill")
                .textSelection(.enabled)
                .lineLimit(2)
            HStack {
                Text("The original encrypted workbook was not modified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                Button("New Recovery", action: model.reset)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
