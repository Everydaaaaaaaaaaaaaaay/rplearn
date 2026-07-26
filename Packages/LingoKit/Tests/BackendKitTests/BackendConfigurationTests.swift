import Foundation
import Testing
@testable import BackendKit

@Suite("Backend production configuration")
struct BackendConfigurationTests {
    @Test("all build configurations use production unless explicitly overridden")
    func productionDefaultAndExplicitOverride() {
        let production = BackendConfiguration.live(environment: [:])
        #expect(production.baseURL.absoluteString == "https://rplearn.haruyuki.cn")

        let local = BackendConfiguration.live(
            environment: ["LINGOTRIP_BACKEND_URL": "http://127.0.0.1:8080"]
        )
        #expect(local.baseURL.absoluteString == "http://127.0.0.1:8080")
    }

    @Test("default transport fails bounded network attempts")
    func boundedNetworkWaiting() {
        let configuration = URLSessionBackendTransport.defaultSessionConfiguration()
        #expect(configuration.waitsForConnectivity == false)
        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 120)
    }
}
