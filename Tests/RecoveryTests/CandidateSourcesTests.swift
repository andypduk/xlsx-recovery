import Darwin
import Foundation
@testable import Recovery
import XCTest

final class CandidateSourcesTests: XCTestCase {
    func testMaskSourceResumesAtExactCursor() throws {
        var source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]], cursor: 2)
        XCTAssertEqual(try source.nextBatch(limit: 2)?.candidates, ["b0", "b1"])
        XCTAssertNil(try source.nextBatch(limit: 2))
    }

    func testMaskOrderAndBatchCursorAreStable() throws {
        var source = try MaskCandidateSource(characterSets: [["a", "b"], ["0", "1"]])
        XCTAssertEqual(try source.nextBatch(limit: 3), CandidateBatch(startCursor: 0, candidates: ["a0", "a1", "b0"]))
        XCTAssertEqual(try source.nextBatch(limit: 3), CandidateBatch(startCursor: 3, candidates: ["b1"]))
    }

    func testRejectsEmptyAndOverflowingMasks() {
        XCTAssertThrowsError(try MaskCandidateSource(characterSets: []))
        XCTAssertThrowsError(try MaskCandidateSource(characterSets: [[]]))
        XCTAssertThrowsError(try MaskCandidateSource(characterSets: Array(repeating: ["a", "b"], count: 65)))
    }

    func testMutationsHaveStableOrdering() throws {
        var source = try MutationCandidateSource(baseWords: ["Example"])
        XCTAssertEqual(
            try source.nextBatch(limit: 6)?.candidates,
            ["Example", "example", "EXAMPLE", "Example", "Example1", "Example!"]
        )
    }

    func testWordlistDoesNotMapEntireFileIntoAddressSpace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let wordlist = directory.appendingPathComponent("large-sparse-wordlist.txt")
        FileManager.default.createFile(atPath: wordlist.path, contents: Data("first\n".utf8))
        let writer = try FileHandle(forWritingTo: wordlist)
        try writer.truncate(atOffset: 512 * 1_024 * 1_024)
        try writer.close()

        let before = try virtualMemorySize()
        let source = try WordlistCandidateSource(url: wordlist)
        let after = try withExtendedLifetime(source) { try virtualMemorySize() }
        let growth = after > before ? after - before : 0

        XCTAssertLessThan(growth, 128 * 1_024 * 1_024)
    }

    func testWordlistRejectsAnUnboundedCandidateLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let wordlist = directory.appendingPathComponent("overlong-line.txt")
        try Data(repeating: 0x61, count: 4_097).write(to: wordlist)
        var source = try WordlistCandidateSource(url: wordlist)

        XCTAssertThrowsError(try source.nextBatch(limit: 1))
    }
}

private func virtualMemorySize() throws -> UInt64 {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { throw VMMeasurementError(code: result) }
    return info.virtual_size
}

private struct VMMeasurementError: Error {
    let code: kern_return_t
}
