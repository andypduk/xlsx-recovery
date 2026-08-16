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
}
