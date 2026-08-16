@testable import Recovery
import OfficeCrypto
import XCTest

final class RecoveryEngineTests: XCTestCase {
    private static let parameters = try! Office2013Parameters(
        version: 2013,
        spinCount: 1,
        keyBits: 256,
        salt: Data(repeating: 0, count: 16),
        encryptedVerifier: Data(repeating: 0, count: 16),
        encryptedVerifierHash: Data(repeating: 0, count: 32)
    )
    private static let identity = RecoveryIdentity(fingerprint: "fixture", configurationDigest: "mask")

    func testStopsOnMatchAndReportsCandidate() async throws {
        let source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]])
        let result = try await RecoveryEngine(verifier: FakeVerifier(match: "b1"), batchSize: 2)
            .run(source: source, parameters: Self.parameters, identity: Self.identity)
        XCTAssertEqual(result, .found("b1"))
    }

    func testExhaustionReportsTestedCount() async throws {
        let source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]])
        let result = try await RecoveryEngine(verifier: FakeVerifier(match: nil), batchSize: 3)
            .run(source: source, parameters: Self.parameters, identity: Self.identity)
        XCTAssertEqual(result, .exhausted(tested: 4))
    }

    func testCriticalThermalStateSavesNextUntestedCursor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let checkpointURL = directory.appendingPathComponent("checkpoint.json")
        let source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]])
        let result = try await RecoveryEngine(
            verifier: FakeVerifier(match: nil),
            thermalState: { .critical }
        ).run(source: source, parameters: Self.parameters, identity: Self.identity, checkpointURL: checkpointURL)
        XCTAssertEqual(result, .cancelled(tested: 0))
        XCTAssertEqual(try RecoveryCheckpoint.load(from: checkpointURL, matching: Self.identity).cursor, 0)
    }

    func testSeriousThermalStateHalvesBatchSize() async throws {
        let recorder = BatchRecorder()
        let source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]])
        _ = try await RecoveryEngine(
            verifier: RecordingVerifier(recorder: recorder),
            batchSize: 4,
            thermalState: { .serious }
        ).run(source: source, parameters: Self.parameters, identity: Self.identity)
        let sizes = await recorder.snapshot()
        XCTAssertEqual(sizes, [2, 2])
    }
}

private struct FakeVerifier: CandidateVerifier {
    let match: String?

    func matchingIndex(in candidates: [String], parameters: Office2013Parameters) async throws -> Int? {
        guard let match else { return nil }
        return candidates.firstIndex(of: match)
    }
}

private actor BatchRecorder {
    private(set) var sizes: [Int] = []
    func append(_ size: Int) { sizes.append(size) }
    func snapshot() -> [Int] { sizes }
}

private struct RecordingVerifier: CandidateVerifier {
    let recorder: BatchRecorder

    func matchingIndex(in candidates: [String], parameters: Office2013Parameters) async throws -> Int? {
        await recorder.append(candidates.count)
        return nil
    }
}
