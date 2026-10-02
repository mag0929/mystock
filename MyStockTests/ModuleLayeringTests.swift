import Foundation
import Testing
@testable import MyStock

@Suite("Module layering")
struct ModuleLayeringTests {
    @Test("The features layer is reachable from the test target")
    func featuresLayerReachable() {
        #expect(HoldingsView.self != nil)
    }
}
