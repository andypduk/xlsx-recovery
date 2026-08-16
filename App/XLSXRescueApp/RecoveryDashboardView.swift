import SwiftUI

struct RecoveryDashboardView: View {
    @Bindable var model: RecoveryViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.open.trianglebadge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("XLSX Rescue").font(.largeTitle.bold())
            Text("Recovery Dashboard").foregroundStyle(.secondary)
            Text("App scaffolding ready").padding().background(.quaternary, in: .rect(cornerRadius: 10))
        }
        .padding(32)
    }
}
