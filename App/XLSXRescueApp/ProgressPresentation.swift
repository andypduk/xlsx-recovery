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
}
