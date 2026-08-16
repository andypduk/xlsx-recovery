@testable import OfficeContainer
import XCTest

final class CompoundFileTests: XCTestCase {
    func testRejectsNonCompoundFile() {
        XCTAssertThrowsError(try CompoundFile(data: Data(repeating: 0, count: 512))) {
            XCTAssertEqual($0 as? CompoundFileError, .invalidHeader)
        }
    }

    func testRejectsTruncatedHeader() {
        XCTAssertThrowsError(try CompoundFile(data: Data([0xD0,0xCF,0x11,0xE0])))
    }
}
