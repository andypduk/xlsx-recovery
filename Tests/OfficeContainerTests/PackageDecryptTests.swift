@testable import OfficeContainer
import XCTest

final class PackageDecryptTests:XCTestCase {
    func testOOXMLValidatorAcceptsRequiredEntries() throws {
        var data=Data([0x50,0x4b,0x03,0x04]); data.append(Data("[Content_Types].xml _rels/.rels xl/workbook.xml".utf8))
        XCTAssertNoThrow(try OOXMLValidator.validate(data))
    }
    func testOOXMLValidatorRejectsMissingEntries(){ XCTAssertThrowsError(try OOXMLValidator.validate(Data([0x50,0x4b,0x03,0x04]))) }
    func testExporterNeverOverwritesSource() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:dir)}; let source=dir.appendingPathComponent("book.xlsx"); try Data("source".utf8).write(to:source)
        XCTAssertThrowsError(try TransactionalExporter.publish(Data(),source:source,output:source)); XCTAssertEqual(try Data(contentsOf:source),Data("source".utf8))
    }
}
