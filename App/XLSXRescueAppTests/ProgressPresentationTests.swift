import XCTest
@testable import XLSXRescueApp

final class ProgressPresentationTests: XCTestCase {
    func testCountAndRateFormatting() {
        XCTAssertEqual(ProgressPresentation.formatCount(0), "0")
        XCTAssertEqual(ProgressPresentation.formatCount(1_250), "1,250")
        XCTAssertEqual(ProgressPresentation.formatCount(12_500_000), "12,500,000")
        XCTAssertEqual(ProgressPresentation(candidatesPerSecond: 0).rateText, "—")
        XCTAssertEqual(ProgressPresentation(candidatesPerSecond: 1_250).rateText, "1,250/s")
    }

    func testBoundedPercentageAndETA() {
        let value = ProgressPresentation(tested: 250, total: 1_000, candidatesPerSecond: 50, elapsedSeconds: 65)
        XCTAssertEqual(value.fraction, 0.25)
        XCTAssertEqual(value.percentageText, "25.0%")
        XCTAssertEqual(value.elapsedText, "1m 05s")
        XCTAssertEqual(value.etaText, "15s")
        XCTAssertEqual(ProgressPresentation(tested: 1_500, total: 1_000).fraction, 1)
    }

    func testUnavailableETA() {
        XCTAssertEqual(ProgressPresentation(total: nil, candidatesPerSecond: 10).etaText, "—")
        XCTAssertEqual(ProgressPresentation(total: 100, candidatesPerSecond: 0).etaText, "—")
        XCTAssertEqual(ProgressPresentation(tested: 100, total: 100).etaText, "Complete")
    }
}
