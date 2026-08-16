import SwiftUI

struct ErrorBanner: View {
    let error: AppError
    let retry: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(error.title).font(.headline)
                Text(error.message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Back", action: retry)
            Button("Reset", action: reset)
        }
        .padding(16)
        .background(.orange.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.28)) }
        .accessibilityElement(children: .combine)
    }
}
