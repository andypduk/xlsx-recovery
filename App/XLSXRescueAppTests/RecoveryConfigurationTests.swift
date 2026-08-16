import XCTest
@testable import XLSXRescueApp

final class RecoveryConfigurationTests: XCTestCase {
    func testExactBoundedSearchTotal() throws {
        let value = RecoveryConfiguration(method: .bruteForce(characterSet: "ab", minimumLength: 1, maximumLength: 3))
        XCTAssertEqual(try value.totalCandidates, 14)
        XCTAssertNoThrow(try value.validate())
    }

    func testInvalidRangesAndEmptySetFail() {
        XCTAssertThrowsError(try RecoveryConfiguration(method: .bruteForce(characterSet: "", minimumLength: 1, maximumLength: 2)).validate())
        XCTAssertThrowsError(try RecoveryConfiguration(method: .bruteForce(characterSet: "ab", minimumLength: 4, maximumLength: 2)).validate())
    }

    func testOverflowFails() {
        XCTAssertThrowsError(try RecoveryConfiguration(method: .bruteForce(characterSet: String((0..<100).compactMap(UnicodeScalar.init).map(Character.init)), minimumLength: 1, maximumLength: 32)).validate())
    }

    func testMissingWordlistFails() {
        let value = RecoveryConfiguration(method: .wordlist(URL(fileURLWithPath: "/missing/words.txt")))
        XCTAssertThrowsError(try value.validate(fileExists: { _ in false }))
    }
}
