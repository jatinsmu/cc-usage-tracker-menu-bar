import XCTest
@testable import CCUsageBar

@MainActor
final class UsageViewModelTests: XCTestCase {

    private func makeVM() -> UsageViewModel { UsageViewModel(autoStart: false) }

    private func snapshot(_ json: String) throws -> UsageSnapshot {
        try UsageClient.decode(Data(json.utf8))
    }

    // MARK: - Menu bar label

    func testLabelForNonDataStates() {
        let vm = makeVM()

        vm.state = .loading
        XCTAssertEqual(vm.menuBarLabel, "--")

        vm.state = .noCredentials
        XCTAssertEqual(vm.menuBarLabel, "?")

        vm.state = .tokenExpired
        XCTAssertEqual(vm.menuBarLabel, "!")

        vm.state = .unauthorized
        XCTAssertEqual(vm.menuBarLabel, "!")

        vm.state = .offline(nil)
        XCTAssertEqual(vm.menuBarLabel, "--")
    }

    func testLabelPercentModeRoundsUtilization() throws {
        let vm = makeVM()
        vm.state = .live(try snapshot(#"{ "five_hour": { "utilization": 66.6 }, "limits": [] }"#))
        XCTAssertEqual(vm.menuBarLabel, "67%")
    }

    func testOfflinePreservesLastKnownLabel() throws {
        let vm = makeVM()
        vm.state = .offline(try snapshot(#"{ "five_hour": { "utilization": 40 }, "limits": [] }"#))
        XCTAssertEqual(vm.menuBarLabel, "40%")
        XCTAssertTrue(vm.isOffline)
    }

    // MARK: - Menu bar symbol

    func testSymbolReflectsState() throws {
        let vm = makeVM()

        vm.state = .loading
        XCTAssertEqual(vm.menuBarSymbol, "gauge")

        vm.state = .tokenExpired
        XCTAssertEqual(vm.menuBarSymbol, "exclamationmark.triangle.fill")

        vm.state = .live(try snapshot("""
        { "limits": [ { "kind": "k", "group": "g", "severity": "critical", "is_active": true } ] }
        """))
        XCTAssertEqual(vm.menuBarSymbol, "exclamationmark.triangle.fill")
    }

    // MARK: - isOffline

    func testIsOfflineOnlyForOfflineState() throws {
        let vm = makeVM()
        vm.state = .live(try snapshot("{}"))
        XCTAssertFalse(vm.isOffline)
        vm.state = .offline(nil)
        XCTAssertTrue(vm.isOffline)
    }
}
