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
