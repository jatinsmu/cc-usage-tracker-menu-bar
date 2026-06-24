import XCTest
@testable import CCUsageBar

final class UpdateCheckerTests: XCTestCase {

    // MARK: - isNewer

    func testIsNewerForHigherVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
    }

    func testIsNotNewerForEqualOrLower() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.9", than: "2.0.0"))
    }

    func testIsNewerToleratesLeadingV() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1.0", than: "v1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.0", than: "1.0.0"))
    }

    func testIsNewerHandlesDifferingComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.9"))   // missing = 0
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
    }

    // MARK: - parseLatest

    func testParseLatestPicksZipAsset() {
        let json = Data("""
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/jatinsmu/cc-usage-tracker-menu-bar/releases/tag/v1.2.0",
          "assets": [
            { "name": "notes.txt", "browser_download_url": "https://example.com/notes.txt" },
            { "name": "CCUsageBar.app.zip", "browser_download_url": "https://example.com/CCUsageBar.app.zip" }
          ]
        }
        """.utf8)

        let info = UpdateChecker.parseLatest(json)
        XCTAssertEqual(info?.version, "1.2.0")   // normalized, no "v"
        XCTAssertEqual(info?.assetName, "CCUsageBar.app.zip")
        XCTAssertEqual(info?.assetURL?.absoluteString, "https://example.com/CCUsageBar.app.zip")
    }

    func testParseLatestWithNoZipAssetHasNilAsset() {
        let json = Data("""
        {
          "tag_name": "1.2.0",
          "html_url": "https://example.com/release",
          "assets": [ { "name": "notes.txt", "browser_download_url": "https://example.com/notes.txt" } ]
        }
        """.utf8)

        let info = UpdateChecker.parseLatest(json)
        XCTAssertEqual(info?.version, "1.2.0")
        XCTAssertNil(info?.assetURL)
        XCTAssertNil(info?.assetName)
    }

    func testParseLatestReturnsNilForGarbage() {
        XCTAssertNil(UpdateChecker.parseLatest(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatest(Data("{}".utf8)))  // no tag_name/html_url
    }
}
