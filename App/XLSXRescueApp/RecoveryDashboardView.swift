import SwiftUI

struct RecoveryDashboardView: View {
    @Bindable var model: RecoveryViewModel
    @State private var clipboard = ClipboardService()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if case .failed(let error) = model.state {
                        ErrorBanner(error: error, retry: model.recoverFromFailure, reset: model.reset)
                    }
                    InputPanel(model: model)
                    ConfigurationPanel(model: model)
                    ActiveRecoveryPanel(model: model)
                    ResultPanel(model: model, clipboard: clipboard)
                    safetyFooter
                }
                .frame(maxWidth: 1_080)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let url = FileSelectionService.chooseWorkbook() {
                        model.selectInput(.workbook(url))
                    }
                } label: {
                    Label("Open Workbook", systemImage: "folder")
                }
                .help("Choose an encrypted .xlsx workbook (⌘O)")

                Button(action: model.reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Clear this recovery session")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("XLSX Rescue")
                    .font(.largeTitle.bold())
                Text("Recover an authorized Office 2013 workbook locally on this Mac")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Offline", systemImage: "network.slash")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.quaternary, in: .capsule)
        }
    }

    private var safetyFooter: some View {
        Label(
            "The encrypted source is opened read-only. Decryption is written only to a separate destination you choose.",
            systemImage: "checkmark.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}
