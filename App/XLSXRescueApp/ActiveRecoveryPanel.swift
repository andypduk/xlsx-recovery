import SwiftUI

struct ActiveRecoveryPanel: View {
    @Bindable var model: RecoveryViewModel

    @ViewBuilder var body: some View {
        switch model.state {
        case .recovering(let progress): panel(progress: progress, paused: false)
        case .paused(let checkpoint):
            panel(
                progress: .init(
                    stage: "Paused",
                    tested: checkpoint.tested,
                    total: try? model.configuration.totalCandidates,
                    thermalState: "—"
                ),
                paused: true
            )
        case .inspecting:
            DashboardCard(title: "Inspecting input", systemImage: "magnifyingglass") {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading supported Office encryption parameters…").foregroundStyle(.secondary)
                }
            }
        default: EmptyView()
        }
    }

    private func panel(progress: ProgressPresentation, paused: Bool) -> some View {
        DashboardCard(title: paused ? "Recovery paused" : "3. Recovery in progress", systemImage: paused ? "pause.circle" : "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(progress.stage).font(.title3.weight(.semibold))
                    Spacer()
                    Text(progress.percentageText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Recovery progress")
                        .accessibilityValue(progress.percentageText)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    metric("Tested", progress.testedText, "number")
                    metric("Rate", progress.rateText, "speedometer")
                    metric("Elapsed", progress.elapsedText, "clock")
                    metric("ETA", progress.etaText, "hourglass")
                    metric("Backend", progress.backend, "cpu")
                    metric("Thermal", progress.thermalState, "thermometer.medium")
                }

                HStack {
                    Label(
                        paused ? "Checkpoint saved at the next untested candidate." : "Recovery runs locally and pauses automatically under critical thermal pressure.",
                        systemImage: paused ? "checkmark.circle" : "fan"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if paused {
                        Button("Resume", action: model.resume)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pause", action: model.pause)
                    }
                    Button("Cancel", role: .cancel, action: model.cancel)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(.body, design: .rounded).weight(.medium)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 9))
    }
}
