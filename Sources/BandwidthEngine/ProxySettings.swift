import Foundation
import SystemConfiguration

public struct ProxyEndpoint: Hashable, Sendable {
    public let host: String?
    public let port: Int

    public init(host: String?, port: Int) {
        let normalized = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.host = normalized?.isEmpty == true ? nil : normalized
        self.port = port
    }
}

public struct ProxySettings: Sendable {
    public let endpoints: Set<ProxyEndpoint>

    public init(endpoints: Set<ProxyEndpoint> = []) {
        self.endpoints = endpoints
    }

    public func matches(_ endpoint: NetworkEndpoint) -> Bool {
        guard let port = endpoint.port else { return false }
        let endpointHost = endpoint.host.lowercased()

        return endpoints.contains { proxy in
            guard proxy.port == port else { return false }
            guard let proxyHost = proxy.host else { return endpoint.isLoopback }

            let normalizedProxyHost = proxyHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if normalizedProxyHost == "localhost" || normalizedProxyHost == "::1" || normalizedProxyHost.hasPrefix("127.") {
                return endpoint.isLoopback
            }
            return normalizedProxyHost == endpointHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
    }

    public static func current() -> ProxySettings {
        // Some TUN clients keep a local listener active even when the macOS
        // system proxy switches are off.
        var endpoints: Set<ProxyEndpoint> = [ProxyEndpoint(host: "127.0.0.1", port: 7897)]
        guard let dictionary = SCDynamicStoreCopyProxies(nil) as NSDictionary? else {
            return ProxySettings(endpoints: endpoints)
        }

        let candidates: [(CFString, CFString, CFString)] = [
            (kSCPropNetProxiesHTTPEnable, kSCPropNetProxiesHTTPProxy, kSCPropNetProxiesHTTPPort),
            (kSCPropNetProxiesHTTPSEnable, kSCPropNetProxiesHTTPSProxy, kSCPropNetProxiesHTTPSPort),
            (kSCPropNetProxiesFTPEnable, kSCPropNetProxiesFTPProxy, kSCPropNetProxiesFTPPort),
            (kSCPropNetProxiesSOCKSEnable, kSCPropNetProxiesSOCKSProxy, kSCPropNetProxiesSOCKSPort)
        ]

        for (enabledKey, hostKey, portKey) in candidates {
            let enabled = (dictionary[enabledKey as String] as? NSNumber)?.boolValue ?? false
            let host = dictionary[hostKey as String] as? String
            let port = (dictionary[portKey as String] as? NSNumber)?.intValue ?? 0
            if enabled, port > 0 {
                endpoints.insert(ProxyEndpoint(host: host, port: port))
            }
        }

        return ProxySettings(endpoints: endpoints)
    }
}

public struct RouteClassifier: Sendable {
    public let proxySettings: ProxySettings

    public init(proxySettings: ProxySettings) {
        self.proxySettings = proxySettings
    }

    public func classify(_ connection: ConnectionSnapshot) -> TrafficPath {
        let identity = connection.identity

        if proxySettings.matches(identity.local) || proxySettings.matches(identity.remote) {
            return .proxy
        }

        if identity.local.isLoopback || identity.remote.isLoopback || identity.interfaceName.lowercased() == "lo0" {
            return .local
        }

        return .direct
    }
}
