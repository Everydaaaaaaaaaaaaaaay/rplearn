import Foundation

public struct BackendConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    public static var live: BackendConfiguration {
        live(environment: ProcessInfo.processInfo.environment)
    }

    static func live(environment: [String: String]) -> BackendConfiguration {
        let overrideURL = environment["LINGOTRIP_BACKEND_URL"].flatMap(URL.init(string:))
        #if DEBUG
        if isAppointmentTestBuild {
            if let url = appointmentTestURL ?? overrideURL, url.host?.lowercased() != "rplearn.haruyuki.cn" {
                return BackendConfiguration(baseURL: url)
            }
            return BackendConfiguration(baseURL: URL(string: "http://127.0.0.1:9")!, requestTimeout: 1)
        }
        #endif
        return BackendConfiguration(baseURL: overrideURL ?? URL(string: "https://rplearn.haruyuki.cn")!)
    }

    #if DEBUG
    private static var isAppointmentTestBuild: Bool {
        Bundle.main.bundleIdentifier == "com.tiantian.lingotrip.appointmente2e"
    }

    public static var appointmentTestURL: URL? {
        guard isAppointmentTestBuild,
              let value = Bundle.main.object(forInfoDictionaryKey: "LingoTripAppointmentTestBackend") as? String,
              let url = URL(string: value),
              url.scheme == "https", let host = url.host,
              host.lowercased() != "rplearn.haruyuki.cn" else { return nil }
        return url
    }
    #endif
}
