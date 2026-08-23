import Foundation

#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

public protocol ProxySettingsProviding {
    func currentSettings() -> ProxySettings
}

public struct SystemProxySettingsProvider: ProxySettingsProviding {
    public init() {}

    public func currentSettings() -> ProxySettings {
        #if canImport(SystemConfiguration)
        guard let proxyDictionary = SCDynamicStoreCopyProxies(nil),
              let proxies = proxyDictionary as NSDictionary as? [String: Any] else {
            return ProxySettings()
        }

        var endpoints = Set<ProxyEndpoint>()
        insertProxyEndpoint(
            into: &endpoints,
            proxies: proxies,
            enabledKey: kSCPropNetProxiesHTTPEnable as String,
            hostKey: kSCPropNetProxiesHTTPProxy as String,
            portKey: kSCPropNetProxiesHTTPPort as String
        )
        insertProxyEndpoint(
            into: &endpoints,
            proxies: proxies,
            enabledKey: kSCPropNetProxiesHTTPSEnable as String,
            hostKey: kSCPropNetProxiesHTTPSProxy as String,
            portKey: kSCPropNetProxiesHTTPSPort as String
        )
        insertProxyEndpoint(
            into: &endpoints,
            proxies: proxies,
            enabledKey: kSCPropNetProxiesSOCKSEnable as String,
            hostKey: kSCPropNetProxiesSOCKSProxy as String,
            portKey: kSCPropNetProxiesSOCKSPort as String
        )

        return ProxySettings(endpoints: endpoints)
        #else
        return ProxySettings()
        #endif
    }

    #if canImport(SystemConfiguration)
    private func insertProxyEndpoint(
        into endpoints: inout Set<ProxyEndpoint>,
        proxies: [String: Any],
        enabledKey: String,
        hostKey: String,
        portKey: String
    ) {
        guard number(proxies[enabledKey])?.boolValue == true,
              let port = number(proxies[portKey])?.intValue,
              port > 0 else {
            return
        }

        endpoints.insert(
            ProxyEndpoint(host: proxies[hostKey] as? String, port: port)
        )
    }

    private func number(_ value: Any?) -> NSNumber? {
        if let number = value as? NSNumber {
            return number
        }

        if let int = value as? Int {
            return NSNumber(value: int)
        }

        return nil
    }
    #endif
}
