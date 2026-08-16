@testable import OfficeCrypto
import XCTest

final class OfficeHashParserTests: XCTestCase {
    private let valid = "$office$*2013*100000*256*16*000102030405060708090a0b0c0d0e0f*00112233445566778899aabbccddeeff*000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

    func testParsesOffice2013Verifier() throws {
        let value = try OfficeHashParser.parse(valid)
        XCTAssertEqual(value.version, 2013)
        XCTAssertEqual(value.spinCount, 100_000)
        XCTAssertEqual(value.keyBits, 256)
        XCTAssertEqual(value.salt.count, 16)
        XCTAssertEqual(value.encryptedVerifier.count, 16)
        XCTAssertEqual(value.encryptedVerifierHash.count, 32)
    }

    func testRejectsBadHex() {
        let malformed = valid.replacingOccurrences(of: "00010203", with: "zz010203")
        XCTAssertThrowsError(try OfficeHashParser.parse(malformed)) { error in
            XCTAssertEqual(error as? OfficeHashError, .invalidHex(field: "salt"))
        }
    }

    func testRejectsDeclaredSaltLengthMismatch() {
        let malformed = valid.replacingOccurrences(of: "*16*", with: "*15*")
        XCTAssertThrowsError(try OfficeHashParser.parse(malformed)) { error in
            XCTAssertEqual(error as? OfficeHashError, .invalidLength(field: "salt"))
        }
    }

    func testRejectsUnsupportedVersionAndKeySize() {
        XCTAssertThrowsError(try OfficeHashParser.parse(valid.replacingOccurrences(of: "*2013*", with: "*2010*")))
        XCTAssertThrowsError(try OfficeHashParser.parse(valid.replacingOccurrences(of: "*256*", with: "*128*")))
    }

    func testRejectsExtraFieldsAndNonASCII() {
        XCTAssertThrowsError(try OfficeHashParser.parse(valid + "*extra"))
        XCTAssertThrowsError(try OfficeHashParser.parse(valid + "é"))
    }
}
