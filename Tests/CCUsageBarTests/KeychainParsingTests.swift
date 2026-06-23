import XCTest
@testable import CCUsageBar

final class KeychainParsingTests: XCTestCase {

    func testParseValidCredentials() throws {
        let creds = try KeychainReader.parse(Data("""
        { "claudeAiOauth": {
            "accessToken": "tok_abc",
            "expiresAt": 1750000000000,
            "subscriptionType": "pro",
            "rateLimitTier": "default"
        } }
        """.utf8))

        XCTAssertEqual(creds.accessToken, "tok_abc")
        XCTAssertEqual(creds.subscriptionType, "pro")
        XCTAssertEqual(creds.rateLimitTier, "default")
        // expiresAt is stored in milliseconds; converted to seconds.
        XCTAssertEqual(creds.expiresAt?.timeIntervalSince1970 ?? 0,
                       1_750_000_000, accuracy: 0.001)
    }

    func testParseExpiresAtInSecondsIsNotMisreadAsExpired() throws {
        // A token whose expiresAt is stored in *seconds* (not ms) must not be
        // divided by 1000 — doing so lands in 1970 and makes a fresh token read
        // as expired (the "Session expired" false positive this guards against).
        let oneHourFromNow = Date().timeIntervalSince1970 + 3600  // seconds
        let creds = try KeychainReader.parse(Data("""
        { "claudeAiOauth": {
            "accessToken": "tok",
            "expiresAt": \(Int(oneHourFromNow))
        } }
        """.utf8))

        let exp = try XCTUnwrap(creds.expiresAt)
        XCTAssertGreaterThan(exp, Date(), "seconds-epoch token should not parse as expired")
        XCTAssertEqual(exp.timeIntervalSince1970, oneHourFromNow, accuracy: 1)
    }

    func testDateFromEpochHandlesBothUnits() {
        // 1_700_000_000 s and 1_700_000_000_000 ms are the same instant.
        XCTAssertEqual(KeychainReader.date(fromEpoch: 1_700_000_000).timeIntervalSince1970,
                       1_700_000_000, accuracy: 0.001)
        XCTAssertEqual(KeychainReader.date(fromEpoch: 1_700_000_000_000).timeIntervalSince1970,
                       1_700_000_000, accuracy: 0.001)
    }

    func testParseToleratesMissingOptionalFields() throws {
        let creds = try KeychainReader.parse(Data("""
        { "claudeAiOauth": { "accessToken": "tok" } }
        """.utf8))

        XCTAssertEqual(creds.accessToken, "tok")
        XCTAssertNil(creds.expiresAt)
        XCTAssertNil(creds.subscriptionType)
        XCTAssertNil(creds.rateLimitTier)
    }

    func testParseMissingTokenThrowsParseError() {
        XCTAssertThrowsError(
            try KeychainReader.parse(Data(#"{ "claudeAiOauth": { "foo": "bar" } }"#.utf8))
        ) { error in
            guard case KeychainError.parseError = error else {
                return XCTFail("expected KeychainError.parseError, got \(error)")
            }
        }
    }

    func testParseGarbageThrowsParseError() {
        XCTAssertThrowsError(
            try KeychainReader.parse(Data("not json".utf8))
        ) { error in
            guard case KeychainError.parseError = error else {
                return XCTFail("expected KeychainError.parseError, got \(error)")
            }
        }
    }
}
