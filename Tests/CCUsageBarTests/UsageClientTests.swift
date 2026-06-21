import XCTest
@testable import CCUsageBar

final class UsageClientTests: XCTestCase {

    private func decode(_ json: String) throws -> UsageSnapshot {
        try UsageClient.decode(Data(json.utf8))
    }

    func testDecodesFractionalSecondDates() throws {
        let s = try decode(#"{ "five_hour": { "utilization": 1, "resets_at": "2026-06-21T17:10:00.360864+00:00" } }"#)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
    }

    func testDecodesNonFractionalDates() throws {
        let s = try decode(#"{ "five_hour": { "utilization": 1, "resets_at": "2026-06-21T17:10:00+00:00" } }"#)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
    }

    func testUnparseableDateThrows() {
        XCTAssertThrowsError(
            try decode(#"{ "five_hour": { "utilization": 1, "resets_at": "not-a-date" } }"#)
        )
    }

    func testErrorDescriptionsAreHumanReadable() {
        XCTAssertEqual(
            UsageClientError.unauthorized.errorDescription,
            "API returned 401 — token may be expired"
        )
        XCTAssertEqual(
            UsageClientError.rateLimited(retryAfter: 120).errorDescription,
            "Rate limited by API — retry in 120s"
        )
        XCTAssertEqual(
            UsageClientError.httpError(503).errorDescription,
            "API returned HTTP 503"
        )
    }
}
