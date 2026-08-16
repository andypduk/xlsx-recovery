import Foundation

struct RunnerProgress: Equatable, Sendable {
    let stage: String
    let tested: UInt64
    let total: UInt64?
    let candidatesPerSecond: Double
    let elapsedSeconds: TimeInterval
    let backend: String
    let thermalState: String
}

enum RunnerRecoveryResult: Equatable, Sendable {
    case found(RecoveryResultSummary)
    case exhausted(tested: UInt64)
    case paused(CheckpointSummary)
    case cancelled
}

protocol RecoveryRunning: Sendable {
    func inspect(_ input: RecoveryInput) async throws -> InputSummary
    func recover(
        input: InputSummary,
        configuration: RecoveryConfiguration,
        resume: Bool,
        progress: @escaping @Sendable (RunnerProgress) -> Void
    ) async throws -> RunnerRecoveryResult
    func requestPause()
    func requestCancel()
    func decrypt(result: RecoveryResultSummary, to output: URL) async throws
}
