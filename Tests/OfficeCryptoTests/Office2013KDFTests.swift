@testable import OfficeCrypto
import XCTest

final class Office2013KDFTests: XCTestCase {
    // Hashcat mode 9600 upstream self-test vector. The disposable password is "hashcat".
    private static let fixtureVerifier = "$office$*2013*100000*256*16*67805436882475302087847656644837*0c392d3b9ca889656d1e615c54f9f3c9*612b79e33b96322c3253fc8a0f314463cd76bc4efe1352f7efffca0f374f7e4b"

    func testCorrectPasswordMatchesIndependentHashcatVector() throws {
        let parameters = try OfficeHashParser.parse(Self.fixtureVerifier)
        XCTAssertTrue(try CPUOffice2013Verifier.verify(candidate: "hashcat", against: parameters))
    }

    func testWrongAndCaseChangedPasswordsDoNotMatch() throws {
        let parameters = try OfficeHashParser.parse(Self.fixtureVerifier)
        XCTAssertFalse(try CPUOffice2013Verifier.verify(candidate: "Hashcat", against: parameters))
        XCTAssertFalse(try CPUOffice2013Verifier.verify(candidate: "wrong", against: parameters))
    }

    func testPasswordEncodingIsUTF16LittleEndian() {
        XCTAssertEqual(
            Array(Office2013KDF.passwordBytes("A😀")),
            [0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE]
        )
    }

    func testEmbeddedNullCandidateIsRejected() throws {
        let parameters = try OfficeHashParser.parse(Self.fixtureVerifier)
        XCTAssertThrowsError(try CPUOffice2013Verifier.verify(candidate: "hash\0cat", against: parameters))
    }
}
