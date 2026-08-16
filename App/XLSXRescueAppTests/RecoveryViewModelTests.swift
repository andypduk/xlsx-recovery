import XCTest
@testable import XLSXRescueApp

@MainActor
final class RecoveryViewModelTests: XCTestCase {
    func testInspectRecoverPauseResumeAndReset() async {
        let runner = MockRecoveryRunner()
        let model = RecoveryViewModel(runner: runner)
        model.hashText = "$office$*fixture"
        model.validateHash()
        await settle()
        guard case .ready = model.state else { return XCTFail("Expected ready") }

        runner.result = .paused(.init(tested: 4, checkpointURL: nil))
        model.start()
        await settle()
        guard case .paused = model.state else { return XCTFail("Expected paused") }

        runner.result = .found(.init(password: "secret", sourceWorkbook: nil))
        model.resume()
        await settle()
        XCTAssertEqual(model.state, .recovered(.init(password: "secret", sourceWorkbook: nil)))
        XCTAssertFalse(model.passwordRevealed)

        model.reset()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.hashText, "")
    }

    func testIllegalStartLeavesIdleStateUnchanged() {
        let model = RecoveryViewModel(runner: MockRecoveryRunner())
        model.start()
        XCTAssertEqual(model.state, .idle)
    }

    func testFailureCanReturnToReadyInput() async {
        let runner = MockRecoveryRunner()
        let model = RecoveryViewModel(runner: runner)
        model.hashText = "$office$*fixture"
        model.validateHash()
        await settle()
        runner.result = .exhausted(tested: 10)
        model.start()
        await settle()
        guard case .failed = model.state else { return XCTFail("Expected failed") }
        model.recoverFromFailure()
        guard case .ready = model.state else { return XCTFail("Expected ready") }
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

private final class MockRecoveryRunner: RecoveryRunning, @unchecked Sendable {
    var result: RunnerRecoveryResult = .found(.init(password: "password", sourceWorkbook: nil))

    func inspect(_ input: RecoveryInput) async throws -> InputSummary {
        .init(title: "Office 2013 verifier", detail: "AES-256 · SHA-512", input: input)
    }

    func recover(
        input: InputSummary,
        configuration: RecoveryConfiguration,
        resume: Bool,
        progress: @escaping @Sendable (RunnerProgress) -> Void
    ) async throws -> RunnerRecoveryResult { result }

    func requestPause() {}
    func requestCancel() {}
    func decrypt(result: RecoveryResultSummary, to output: URL) async throws {}
}
