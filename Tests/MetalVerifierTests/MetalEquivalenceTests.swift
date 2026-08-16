import Metal
import OfficeCrypto
import Recovery
@testable import MetalVerifier
import XCTest

final class MetalEquivalenceTests:XCTestCase {
    private let verifierString="$office$*2013*100000*256*16*67805436882475302087847656644837*0c392d3b9ca889656d1e615c54f9f3c9*612b79e33b96322c3253fc8a0f314463cd76bc4efe1352f7efffca0f374f7e4b"
    func testMetalMatchesIndependentVector() async throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil)
        let parameters=try OfficeHashParser.parse(verifierString)
        let candidates=["", "a", "wrong", "pässword", "😀", "hashcat", "Hashcat", String(repeating: "z", count: 32)]
        let cpu=try await CPUOffice2013BatchVerifier().matchingIndex(in:candidates,parameters:parameters)
        let gpu=try await MetalOffice2013Verifier().matchingIndex(in:candidates,parameters:parameters)
        XCTAssertEqual(gpu,cpu); XCTAssertEqual(gpu,5)
    }
}
