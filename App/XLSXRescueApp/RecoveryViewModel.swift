import Foundation
import Observation

@MainActor
@Observable
final class RecoveryViewModel {
    var state: RecoverySessionState = .idle
    var configuration = RecoveryConfiguration()
    var hashText = ""
    var passwordRevealed = false

    @ObservationIgnored private let runner: (any RecoveryRunning)?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    private(set) var selectedInput: InputSummary?

    init(runner: (any RecoveryRunning)? = nil) {
        self.runner = runner
    }

    deinit { operation?.cancel() }

    func selectInput(_ input: RecoveryInput) {
        guard canSelectInput else { return }
        guard let runner else {
            state = .failed(.init(title: "Recovery unavailable", message: "The recovery service is not configured."))
            return
        }
        beginOperation()
        state = .inspecting
        let currentID = operationID
        operation = Task { [weak self] in
            do {
                let summary = try await runner.inspect(input)
                guard let self, self.operationID == currentID else { return }
                self.selectedInput = summary
                self.state = .ready(summary)
            } catch {
                guard let self, self.operationID == currentID else { return }
                self.state = .failed(.redacted(error, title: "Input could not be validated"))
            }
        }
    }

    func validateHash() {
        let normalized = hashText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            state = .failed(.init(title: "Office verifier is empty", message: "Paste a $office$ verifier, then choose Validate."))
            return
        }
        hashText = normalized
        selectInput(.officeHash(normalized))
    }

    func start() {
        guard case .ready(let input) = state else { return }
        runRecovery(input: input, resume: false)
    }

    func pause() {
        guard case .recovering = state else { return }
        runner?.requestPause()
    }

    func resume() {
        guard case .paused = state, let selectedInput else { return }
        runRecovery(input: selectedInput, resume: true)
    }

    func cancel() {
        switch state {
        case .recovering:
            runner?.requestCancel()
        case .paused:
            runner?.requestCancel()
            if let selectedInput { state = .ready(selectedInput) }
            else { state = .idle }
        default:
            return
        }
    }

    func reset() {
        runner?.requestCancel()
        beginOperation()
        selectedInput = nil
        hashText = ""
        passwordRevealed = false
        state = .idle
    }

    func export(to output: URL) {
        guard case .recovered(let result) = state, result.sourceWorkbook != nil, let runner else { return }
        beginOperation()
        state = .decrypting
        let currentID = operationID
        operation = Task { [weak self] in
            do {
                try await runner.decrypt(result: result, to: output)
                guard let self, self.operationID == currentID else { return }
                self.state = .completed(output: output)
            } catch {
                guard let self, self.operationID == currentID else { return }
                self.state = .failed(.redacted(error, title: "Export failed"))
            }
        }
    }

    func recoverFromFailure() {
        guard case .failed = state else { return }
        if let selectedInput { state = .ready(selectedInput) }
        else { state = .idle }
    }

    private var canSelectInput: Bool {
        switch state {
        case .idle, .ready, .failed, .completed: true
        default: false
        }
    }

    private func runRecovery(input: InputSummary, resume: Bool) {
        guard let runner else { return }
        do {
            try configuration.validate()
        } catch {
            state = .failed(.init(title: "Invalid recovery settings", message: configurationMessage(for: error)))
            return
        }

        beginOperation()
        let currentID = operationID
        let total = try? configuration.totalCandidates
        state = .recovering(.init(stage: resume ? "Resuming" : "Starting", total: total))
        let progressHandler: @Sendable (RunnerProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.operationID == currentID else { return }
                self.state = .recovering(.init(progress: progress))
            }
        }
        operation = Task { [weak self] in
            do {
                let result = try await runner.recover(
                    input: input,
                    configuration: self?.configuration ?? RecoveryConfiguration(),
                    resume: resume,
                    progress: progressHandler
                )
                guard let self, self.operationID == currentID else { return }
                switch result {
                case .found(let summary):
                    self.passwordRevealed = false
                    self.state = .recovered(summary)
                case .exhausted(let tested):
                    self.state = .failed(.init(
                        title: "Password not found",
                        message: "The configured search completed after \(ProgressPresentation.formatCount(tested)) candidates."
                    ))
                case .paused(let checkpoint): self.state = .paused(checkpoint)
                case .cancelled: self.state = .ready(input)
                }
            } catch {
                guard let self, self.operationID == currentID else { return }
                self.state = .failed(.redacted(error))
            }
        }
    }

    private func beginOperation() {
        operationID = UUID()
        operation?.cancel()
        operation = nil
    }

    private func configurationMessage(for error: Error) -> String {
        switch error {
        case ConfigurationError.emptyCharacterSet:
            "Enter at least one character to test."
        case ConfigurationError.invalidLengthRange:
            "Use a minimum length of at least 1 and a maximum from the minimum through 32."
        case ConfigurationError.searchSpaceOverflow:
            "This search space is too large. Shorten the range or character set."
        case ConfigurationError.wordlistUnavailable:
            "Choose a readable wordlist file."
        default:
            "Review the recovery settings and try again."
        }
    }
}
