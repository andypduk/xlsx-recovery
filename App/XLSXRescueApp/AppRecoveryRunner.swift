import Foundation
import MetalVerifier
import OfficeContainer
import OfficeCrypto
import Recovery

struct AppBackend: Sendable {
    let verifier: any CandidateVerifier
    let label: String
}

final class AppRecoveryRunner: RecoveryRunning, @unchecked Sendable {
    typealias BackendProvider = @Sendable (Office2013Parameters) async -> AppBackend

    private let checkpointDirectory: URL
    private let backendProvider: BackendProvider
    private let control = RecoveryControl()

    init(
        checkpointDirectory: URL? = nil,
        backendProvider: @escaping BackendProvider = { parameters in
            let selected = await BackendSelector.selection(parameters: parameters)
            return AppBackend(verifier: selected.verifier, label: selected.label)
        }
    ) {
        self.checkpointDirectory = checkpointDirectory ?? Self.defaultCheckpointDirectory
        self.backendProvider = backendProvider
    }

    func inspect(_ input: RecoveryInput) async throws -> InputSummary {
        let parameters = try parameters(for: input)
        let detail = "AES-\(parameters.keyBits) · SHA-512 · \(ProgressPresentation.formatCount(UInt64(parameters.spinCount))) iterations"
        switch input {
        case .workbook(let url):
            return .init(title: url.lastPathComponent, detail: detail, input: input)
        case .officeHash:
            return .init(title: "Office 2013 verifier", detail: detail, input: input)
        }
    }

    func recover(
        input: InputSummary,
        configuration: RecoveryConfiguration,
        resume: Bool,
        progress: @escaping @Sendable (RunnerProgress) -> Void
    ) async throws -> RunnerRecoveryResult {
        control.reset()
        let parameters = try parameters(for: input.input)
        let backend = await backendProvider(parameters)
        let identity = try identity(parameters: parameters, configuration: configuration)
        let checkpointURL = try checkpointURL(for: identity)
        let checkpoint = resume ? try RecoveryCheckpoint.load(from: checkpointURL, matching: identity) : nil
        let total = try totalCandidates(configuration)
        let sources = try candidateSources(configuration, checkpoint: checkpoint)
        let clock = ContinuousClock()
        let started = clock.now
        let initialElapsed = checkpoint?.elapsedSeconds ?? 0
        var elapsedBeforeStage = initialElapsed
        var tested = checkpoint?.tested ?? 0

        for source in sources {
            let engine = RecoveryEngine(
                verifier: backend.verifier,
                batchSize: 256,
                shouldCancel: { [control] in control.request != .none },
                progress: { snapshot in
                    let duration = started.duration(to: clock.now)
                    let currentElapsed = initialElapsed
                        + Double(duration.components.seconds)
                        + Double(duration.components.attoseconds) / 1e18
                    progress(.init(
                        stage: Self.displayStage(snapshot.stage),
                        tested: snapshot.tested,
                        total: total,
                        candidatesPerSecond: currentElapsed > 0 ? Double(snapshot.tested) / currentElapsed : 0,
                        elapsedSeconds: currentElapsed,
                        backend: backend.label,
                        thermalState: Self.thermalLabel(.current)
                    ))
                }
            )
            let result = try await engine.run(
                source: source,
                parameters: parameters,
                identity: identity,
                checkpointURL: checkpointURL,
                initialTested: tested,
                initialElapsed: elapsedBeforeStage
            )
            switch result {
            case .found(let password):
                try? FileManager.default.removeItem(at: checkpointURL)
                return .found(.init(password: password, sourceWorkbook: input.input.workbookURL))
            case .exhausted(let count):
                tested = count
                let duration = started.duration(to: clock.now)
                elapsedBeforeStage = initialElapsed
                    + Double(duration.components.seconds)
                    + Double(duration.components.attoseconds) / 1e18
            case .cancelled(let count):
                switch control.request {
                case .cancel:
                    try? FileManager.default.removeItem(at: checkpointURL)
                    return .cancelled
                case .pause, .none:
                    return .paused(.init(tested: count, checkpointURL: checkpointURL))
                }
            }
        }
        try? FileManager.default.removeItem(at: checkpointURL)
        return .exhausted(tested: tested)
    }

    func requestPause() { control.set(.pause) }
    func requestCancel() { control.set(.cancel) }

    func decrypt(result: RecoveryResultSummary, to output: URL) async throws {
        guard let source = result.sourceWorkbook else {
            throw AppError(title: "Workbook required", message: "Select the encrypted workbook before exporting an unencrypted copy.")
        }
        let file = try CompoundFile.openReadOnly(source)
        let descriptor = try AgileEncryptionInfo.parse(file.readStream(named: "EncryptionInfo", maxBytes: 1_048_576))
        let encrypted = try file.readStream(named: "EncryptedPackage")
        let decrypted = try EncryptedPackage.decrypt(stream: encrypted, descriptor: descriptor, password: result.password)
        try OOXMLValidator.validate(decrypted)
        try TransactionalExporter.publish(decrypted, source: source, output: output, overwrite: true)
    }

    private func parameters(for input: RecoveryInput) throws -> Office2013Parameters {
        switch input {
        case .officeHash(let text): return try OfficeHashParser.parse(text)
        case .workbook(let url):
            let file = try CompoundFile.openReadOnly(url)
            let stream = try file.readStream(named: "EncryptionInfo", maxBytes: 1_048_576)
            return try AgileEncryptionInfo.parse(stream).passwordParameters
        }
    }

    private func identity(
        parameters: Office2013Parameters,
        configuration: RecoveryConfiguration
    ) throws -> RecoveryIdentity {
        let fingerprint = RecoveryIdentity.digest(
            parameters.salt + parameters.encryptedVerifier + parameters.encryptedVerifierHash
        )
        let description: String
        switch configuration.method {
        case .wordlist(let url):
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? NSNumber
            let modified = attributes[.modificationDate] as? Date
            description = "wordlist|\(url.standardizedFileURL.path)|\(size?.uint64Value ?? 0)|\(modified?.timeIntervalSince1970 ?? 0)"
        case .bruteForce(let characters, let minimum, let maximum):
            description = "bruteforce|\(characters)|\(minimum)|\(maximum)"
        }
        return .init(
            fingerprint: fingerprint,
            configurationDigest: RecoveryIdentity.digest(Data(description.utf8))
        )
    }

    private func checkpointURL(for identity: RecoveryIdentity) throws -> URL {
        try FileManager.default.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)
        return checkpointDirectory.appendingPathComponent(
            "\(identity.fingerprint.prefix(16))-\(identity.configurationDigest.prefix(16)).json"
        )
    }

    private func candidateSources(
        _ configuration: RecoveryConfiguration,
        checkpoint: RecoveryCheckpoint?
    ) throws -> [AnyCandidateSource] {
        switch configuration.method {
        case .wordlist(let url):
            let stage = "wordlist"
            let cursor = checkpoint?.stage == stage ? checkpoint?.cursor ?? 0 : 0
            return [AnyCandidateSource(try WordlistCandidateSource(stageID: stage, url: url, cursor: cursor))]
        case .bruteForce(let characterSet, let minimum, let maximum):
            var seen = Set<Character>()
            let characters = characterSet.filter { seen.insert($0).inserted }
            let resumeLength = checkpoint.flatMap(Self.length(from:))
            return try (minimum...maximum).compactMap { length in
                if let resumeLength, length < resumeLength { return nil }
                let stage = "bruteforce-\(length)"
                let cursor = checkpoint?.stage == stage ? checkpoint?.cursor ?? 0 : 0
                return AnyCandidateSource(try MaskCandidateSource(
                    stageID: stage,
                    characterSets: Array(repeating: characters, count: length),
                    cursor: cursor
                ))
            }
        }
    }

    private func totalCandidates(_ configuration: RecoveryConfiguration) throws -> UInt64? {
        switch configuration.method {
        case .bruteForce: return try configuration.totalCandidates
        case .wordlist(let url):
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else { return 0 }
            var lines: UInt64 = 0
            var inLine = false
            for byte in data {
                if byte == 0x0A || byte == 0x0D {
                    if inLine { lines += 1; inLine = false }
                } else { inLine = true }
            }
            if inLine { lines += 1 }
            return lines
        }
    }

    private static func length(from checkpoint: RecoveryCheckpoint) -> Int? {
        Int(checkpoint.stage.split(separator: "-").last ?? "")
    }

    private static func displayStage(_ stage: String) -> String {
        if let length = stage.split(separator: "-").last, stage.hasPrefix("bruteforce-") {
            return "Brute force · length \(length)"
        }
        return "Wordlist"
    }

    private static func thermalLabel(_ state: RecoveryThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    private static var defaultCheckpointDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("XLSX Rescue/Checkpoints", isDirectory: true)
    }
}

private enum RecoveryControlRequest: Int, Sendable {
    case none
    case pause
    case cancel
}

private final class RecoveryControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RecoveryControlRequest = .none

    var request: RecoveryControlRequest {
        lock.withLock { stored }
    }

    func reset() {
        lock.withLock { stored = .none }
    }

    func set(_ value: RecoveryControlRequest) {
        lock.withLock {
            if value.rawValue > stored.rawValue { stored = value }
        }
    }
}

private extension RecoveryInput {
    var workbookURL: URL? {
        guard case .workbook(let url) = self else { return nil }
        return url
    }
}
