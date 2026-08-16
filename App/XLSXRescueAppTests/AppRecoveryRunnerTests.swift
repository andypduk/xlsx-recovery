import Foundation
import OfficeCrypto
import Recovery
import XCTest
@testable import XLSXRescueApp

final class AppRecoveryRunnerTests: XCTestCase {
    private let verifier = "$office$*2013*100000*256*16*67805436882475302087847656644837*0c392d3b9ca889656d1e615c54f9f3c9*612b79e33b96322c3253fc8a0f314463cd76bc4efe1352f7efffca0f374f7e4b"

    func testInspectsOfficeVerifierWithoutHidingIt() async throws {
        let runner = makeRunner(directory: temporaryDirectory())
        let summary = try await runner.inspect(.officeHash(verifier))
        XCTAssertEqual(summary.title, "Office 2013 verifier")
        XCTAssertTrue(summary.detail.contains("100,000 iterations"))
        XCTAssertEqual(summary.input, .officeHash(verifier))
    }

    func testRecoversFromSmallWordlist() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let words = directory.appendingPathComponent("words.txt")
        try Data("wrong\nhashcat\nlater\n".utf8).write(to: words)
        let runner = makeRunner(directory: directory)
        let input = try await runner.inspect(.officeHash(verifier))
        let result = try await runner.recover(
            input: input,
            configuration: .init(method: .wordlist(words)),
            resume: false,
            progress: { _ in }
        )
        XCTAssertEqual(result, .found(.init(password: "hashcat", sourceWorkbook: nil)))
    }

    private func makeRunner(directory: URL) -> AppRecoveryRunner {
        AppRecoveryRunner(checkpointDirectory: directory) { _ in
            AppBackend(verifier: FixtureVerifier(), label: "Test CPU")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private struct FixtureVerifier: CandidateVerifier {
    func matchingIndex(in candidates: [String], parameters: Office2013Parameters) async throws -> Int? {
        candidates.firstIndex(of: "hashcat")
    }
}
