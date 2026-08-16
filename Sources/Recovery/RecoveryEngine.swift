import Foundation
import OfficeCrypto

public protocol CandidateVerifier: Sendable {
    func matchingIndex(
        in candidates: [String],
        parameters: Office2013Parameters
    ) async throws -> Int?
}

public struct CPUOffice2013BatchVerifier: CandidateVerifier {
    public init() {}

    public func matchingIndex(
        in candidates: [String],
        parameters: Office2013Parameters
    ) async throws -> Int? {
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            if try CPUOffice2013Verifier.verify(candidate: candidate, against: parameters) {
                return index
            }
        }
        return nil
    }
}

public enum RecoveryResult: Equatable, Sendable {
    case found(String)
    case exhausted(tested: UInt64)
    case cancelled(tested: UInt64)
}

public enum RecoveryThermalState: Sendable {
    case nominal
    case fair
    case serious
    case critical

    public static var current: Self {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}

public struct ProgressSnapshot: Equatable, Sendable {
    public let stage: String
    public let tested: UInt64
    public let elapsedSeconds: TimeInterval
    public let candidatesPerSecond: Double
}

public struct RecoveryEngine: Sendable {
    public typealias ProgressHandler = @Sendable (ProgressSnapshot) -> Void

    private let verifier: any CandidateVerifier
    private let batchSize: Int
    private let shouldCancel: @Sendable () -> Bool
    private let thermalState: @Sendable () -> RecoveryThermalState
    private let progress: ProgressHandler

    public init(
        verifier: any CandidateVerifier,
        batchSize: Int = 256,
        shouldCancel: @escaping @Sendable () -> Bool = { false },
        thermalState: @escaping @Sendable () -> RecoveryThermalState = { .current },
        progress: @escaping ProgressHandler = { _ in }
    ) {
        precondition(batchSize > 0)
        self.verifier = verifier
        self.batchSize = batchSize
        self.shouldCancel = shouldCancel
        self.thermalState = thermalState
        self.progress = progress
    }

    public func run<S: CandidateSource>(
        source initialSource: S,
        parameters: Office2013Parameters,
        identity: RecoveryIdentity,
        checkpointURL: URL? = nil,
        initialTested: UInt64 = 0,
        initialElapsed: TimeInterval = 0
    ) async throws -> RecoveryResult {
        var source = initialSource
        var tested = initialTested
        let started = ContinuousClock.now
        var lastProgress = started

        while true {
            if shouldCancel() || Task.isCancelled || thermalState() == .critical {
                try saveCheckpoint(source: source, identity: identity, tested: tested,
                                   elapsed: initialElapsed + elapsed(since: started), to: checkpointURL)
                return .cancelled(tested: tested)
            }

            guard let batch = try source.nextBatch(limit: effectiveBatchSize()) else {
                return .exhausted(tested: tested)
            }
            if let match = try await verifier.matchingIndex(in: batch.candidates, parameters: parameters) {
                precondition(batch.candidates.indices.contains(match))
                return .found(batch.candidates[match])
            }
            tested += UInt64(batch.candidates.count)

            let now = ContinuousClock.now
            if now - lastProgress >= .seconds(1) {
                let totalElapsed = initialElapsed + elapsed(since: started)
                progress(.init(
                    stage: source.stageID,
                    tested: tested,
                    elapsedSeconds: totalElapsed,
                    candidatesPerSecond: totalElapsed > 0 ? Double(tested) / totalElapsed : 0
                ))
                lastProgress = now
                try saveCheckpoint(source: source, identity: identity, tested: tested,
                                   elapsed: totalElapsed, to: checkpointURL)
            }
        }
    }

    private func effectiveBatchSize() -> Int {
        thermalState() == .serious ? max(1, batchSize / 2) : batchSize
    }

    private func elapsed(since start: ContinuousClock.Instant) -> TimeInterval {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func saveCheckpoint<S: CandidateSource>(
        source: S,
        identity: RecoveryIdentity,
        tested: UInt64,
        elapsed: TimeInterval,
        to url: URL?
    ) throws {
        guard let url else { return }
        try RecoveryCheckpoint(
            identity: identity,
            stage: source.stageID,
            cursor: source.cursor,
            tested: tested,
            elapsedSeconds: elapsed
        ).saveAtomically(to: url)
    }
}
