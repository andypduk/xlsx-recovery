@testable import Recovery
import XCTest

final class CheckpointTests: XCTestCase {
    func testCheckpointRejectsDifferentIdentity() throws {
        let identity = RecoveryIdentity(fingerprint: "aaa", configurationDigest: "config")
        let checkpoint = RecoveryCheckpoint(identity: identity, stage: "mask-1", cursor: 42, tested: 42)
        XCTAssertThrowsError(try checkpoint.validate(identity: .init(fingerprint: "bbb", configurationDigest: "config"))) {
            XCTAssertEqual($0 as? CheckpointError, .identityMismatch)
        }
    }

    func testCheckpointRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recovery.json")
        let identity = RecoveryIdentity(fingerprint: "aaa", configurationDigest: "config")
        let value = RecoveryCheckpoint(identity: identity, stage: "mask-1", cursor: 42, tested: 40, elapsedSeconds: 1.5)
        try value.saveAtomically(to: url)
        XCTAssertEqual(try RecoveryCheckpoint.load(from: url, matching: identity), value)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }
}
