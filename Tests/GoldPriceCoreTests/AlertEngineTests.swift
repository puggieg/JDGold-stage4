import XCTest
@testable import GoldPriceCore

final class AlertEngineTests: XCTestCase {
    // 直接复用 --selftest 的断言，避免两套实现和两套测试产生分歧。
    func testSharedScenarios() {
        for scenario in CoreSelfTests.cases {
            do { try scenario.run() }
            catch { XCTFail("\(scenario.name)：\(error)") }
        }
    }
}
