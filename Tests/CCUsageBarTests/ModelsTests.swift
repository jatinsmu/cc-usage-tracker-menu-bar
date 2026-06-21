import XCTest
@testable import CCUsageBar

final class ModelsTests: XCTestCase {

    private func decode(_ json: String) throws -> UsageSnapshot {
        try UsageClient.decode(Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodePercentPlan() throws {
        let s = try decode("""
        {
          "five_hour": { "utilization": 92.5, "resets_at": "2026-06-21T17:10:00.360864+00:00" },
          "seven_day": { "utilization": 18.0, "resets_at": "2026-06-28T00:00:00+00:00" },
          "limits": [
            { "kind": "rate_limit", "group": "five_hour", "percent": 93,
              "severity": "critical", "is_active": true }
          ]
        }
        """)

        XCTAssertEqual(s.fiveHour?.utilization, 92.5)
        XCTAssertEqual(s.sevenDay?.utilization, 18.0)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertEqual(s.activeSeverity, .critical)
    }

    func testDecodeMissingFieldsAreNilNotFatal() throws {
        let s = try decode("{}")
        XCTAssertNil(s.fiveHour)
        XCTAssertNil(s.sevenDay)
        XCTAssertTrue(s.limits.isEmpty)
        XCTAssertEqual(s.activeSeverity, .normal)
    }

    func testFetchedAtIsInjectedAtDecodeTime() throws {
        let before = Date()
        let s = try decode("{}")
        XCTAssertGreaterThanOrEqual(s.fetchedAt.timeIntervalSince1970,
                                    before.timeIntervalSince1970 - 1)
    }

    // MARK: - activeSeverity

    func testActiveSeverityPicksActiveLimit() throws {
        let s = try decode("""
        { "limits": [
            { "kind": "k", "group": "g", "severity": "normal",  "is_active": false },
            { "kind": "k", "group": "g", "severity": "warning", "is_active": true }
        ] }
        """)
        XCTAssertEqual(s.activeSeverity, .warning)
    }

    func testActiveSeverityDefaultsNormalWhenNoneActive() throws {
        let s = try decode("""
        { "limits": [ { "kind": "k", "group": "g", "severity": "critical", "is_active": false } ] }
        """)
        XCTAssertEqual(s.activeSeverity, .normal)
    }

    // MARK: - Severity glyphs

    func testSeveritySymbolNames() {
        XCTAssertEqual(Severity.normal.symbolName,   "gauge.with.dots.needle.33percent")
        XCTAssertEqual(Severity.warning.symbolName,  "gauge.with.dots.needle.67percent")
        XCTAssertEqual(Severity.critical.symbolName, "exclamationmark.triangle.fill")
    }
}
