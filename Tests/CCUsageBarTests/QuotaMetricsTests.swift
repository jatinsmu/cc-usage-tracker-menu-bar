import XCTest
@testable import CCUsageBar

final class QuotaMetricsTests: XCTestCase {

    func testNilWhenNoResetTime() {
        XCTAssertNil(windowElapsedFraction(resetsAt: nil, length: 100))
    }

    func testHalfwayThroughWindow() {
        let now = Date()
        let resets = now.addingTimeInterval(50)   // 50s left of a 100s window
        let f = windowElapsedFraction(resetsAt: resets, length: 100, now: now)
        XCTAssertEqual(f ?? -1, 0.5, accuracy: 0.0001)
    }

    func testNilWhenResetIsInThePast() {
        let now = Date()
        let resets = now.addingTimeInterval(-10)
        XCTAssertNil(windowElapsedFraction(resetsAt: resets, length: 100, now: now))
    }

    func testNilWhenResetIsBeyondOneWindow() {
        // A reset further out than the window length is inconsistent — don't guess.
        let now = Date()
        let resets = now.addingTimeInterval(500)
        XCTAssertNil(windowElapsedFraction(resetsAt: resets, length: 100, now: now))
    }

    func testWindowLengths() {
        XCTAssertEqual(QuotaWindowKind.fiveHour.length, 5 * 60 * 60)
        XCTAssertEqual(QuotaWindowKind.sevenDay.length, 7 * 24 * 60 * 60)
    }
}
