import AppKit
import SwiftUI

struct InputPanel: View {
    @Bindable var model: RecoveryViewModel

    var body: some View {
        DashboardCard(title: "1. Recovery input", systemImage: "doc.badge.key") {
            HStack(alignment: .top, spacing: 18) {
                workbookPane
                Divider()
                hashPane
            }
        }
        .disabled(model.inputIsBusy)
    }

    private var workbookPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encrypted workbook")
                .font(.subheadline.weight(.semibold))
            VStack(spacing: 10) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 29))
                    .foregroundStyle(.tint)
                if let summary = model.selectedInput, case .workbook = summary.input {
                    Text(summary.title).fontWeight(.medium).lineLimit(1)
                    Text(summary.detail).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Drop an encrypted .xlsx here")
                        .fontWeight(.medium)
                    Text("or choose it using the file browser")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Choose Workbook…") {
                    if let url = FileSelectionService.chooseWorkbook() {
                        model.selectInput(.workbook(url))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o")
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(12)
            .background(.quaternary.opacity(0.65), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.pathExtension.lowercased() == "xlsx" else { return false }
                model.selectInput(.workbook(url))
                return true
            }
            .accessibilityLabel("Encrypted workbook drop area")
        }
        .frame(maxWidth: .infinity)
    }

    private var hashPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Office verifier")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.hashIsValidated {
                    Label("Validated", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            TextEditor(text: $model.hashText)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 112)
                .background(.background.opacity(0.75), in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(.separator) }
                .accessibilityLabel("Visible Office password verifier")
            HStack {
                Button("Paste") {
                    if let value = NSPasteboard.general.string(forType: .string) { model.hashText = value }
                }
                Button("Clear") { model.hashText = "" }
                    .disabled(model.hashText.isEmpty)
                Spacer()
                Button("Validate Hash", action: model.validateHash)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.hashText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("This verifier stays visible and selectable. Screen recordings can capture it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension RecoveryViewModel {
    var inputIsBusy: Bool {
        switch state {
        case .inspecting, .recovering, .decrypting: true
        default: false
        }
    }

    var hashIsValidated: Bool {
        guard let selectedInput, case .officeHash(let selectedHash) = selectedInput.input else { return false }
        return selectedHash == hashText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
