import XCTest
@testable import QuotaCore

final class RelayQuotaTests: XCTestCase {
    func testUsageURLAcceptsTheCLIBase() {
        XCTAssertEqual(
            RelayQuota.usageURL("https://station.example/api/common")?.absoluteString,
            "https://station.example/api/common/v1/usage")
        XCTAssertEqual(
            RelayQuota.usageURL("https://station.example/api/common/v1/")?.absoluteString,
            "https://station.example/api/common/v1/usage")
        XCTAssertEqual(
            RelayQuota.usageURL("https://station.example/api/common/v1/usage")?.absoluteString,
            "https://station.example/api/common/v1/usage")
    }

    func testParsesRemainingDollars() throws {
        let json = """
        {"expires_at":"2027-04-07T07:45:46Z","quota":{"limit":1000,"remaining":250,"unit":"USD","used":750},"unit":"USD"}
        """.data(using: .utf8)!
        let window = try RelayQuota.parse(json)
        XCTAssertTrue(window.title == "中转站余额" || window.title == "Relay balance")
        XCTAssertEqual(window.usedPercent ?? 0, 75, accuracy: 0.01)
        XCTAssertEqual(window.detail, "$250.00 / $1,000.00")
        XCTAssertNotNil(window.resetsAt)
    }
}
