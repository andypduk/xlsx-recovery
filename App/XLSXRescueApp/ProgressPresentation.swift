import Foundation

struct ProgressPresentation: Equatable, Sendable {
    var stage = "Ready"
    var tested: UInt64 = 0
    var total: UInt64?
    var candidatesPerSecond: Double = 0
    var elapsedSeconds: TimeInterval = 0
    var backend = "—"
    var thermalState = "Nominal"

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(tested) / Double(total))
    }

    var percentageText: String {
        guard let fraction else { return "—" }
        return String(format: "%.1f%%", locale: Self.locale, fraction * 100)
    }

    var testedText: String { Self.formatCount(tested) }

    var totalText: String {
        total.map(Self.formatCount) ?? "Unknown"
    }

    var rateText: String {
        guard candidatesPerSecond.isFinite, candidatesPerSecond > 0 else { return "—" }
        return "\(Self.formatCount(UInt64(candidatesPerSecond.rounded())))/s"
    }

    var elapsedText: String { Self.formatDuration(elapsedSeconds) }

    var etaText: String {
        guard let total,
              tested < total,
              candidatesPerSecond.isFinite,
              candidatesPerSecond > 0
        else { return tested >= (total ?? .max) && total != nil ? "Complete" : "—" }
        return Self.formatDuration(Double(total - tested) / candidatesPerSecond)
    }

    init(
        stage: String = "Ready",
        tested: UInt64 = 0,
        total: UInt64? = nil,
        candidatesPerSecond: Double = 0,
        elapsedSeconds: TimeInterval = 0,
        backend: String = "—",
        thermalState: String = "Nominal"
    ) {
        self.stage = stage
        self.tested = tested
        self.total = total
        self.candidatesPerSecond = candidatesPerSecond
        self.elapsedSeconds = elapsedSeconds
        self.backend = backend
        self.thermalState = thermalState
    }

    init(progress: RunnerProgress) {
        self.init(
            stage: progress.stage,
            tested: progress.tested,
            total: progress.total,
            candidatesPerSecond: progress.candidatesPerSecond,
            elapsedSeconds: progress.elapsedSeconds,
            backend: progress.backend,
            thermalState: progress.thermalState
        )
    }

    static func formatCount(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let rounded = UInt64(seconds.rounded())
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600) / 60
        let remainingSeconds = rounded % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(String(format: "%02llu", remainingSeconds))s" }
        return "\(remainingSeconds)s"
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
}
