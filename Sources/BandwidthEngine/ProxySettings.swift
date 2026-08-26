import Foundation
import SystemConfiguration

public struct ProxySettings {
    public let ports: Set<Int>

    public init(ports: Set<Int> = []) {
        self.ports = ports
    }

    public static func current() -> ProxySettings {
        guard let dictionary = SCDynamicStoreCopyProxies(nil) as NSDictionary? else {
            return ProxySettings()
        }

        var ports = Set<Int>()
        let candidates: [(CFString, CFString)] = [
            (kSCPropNetProxiesHTTPEnable, kSCPropNetProxiesHTTPPort),
            (kSCPropNetProxiesHTTPSEnable, kSCPropNetProxiesHTTPSPort),
            (kSCPropNetProxiesFTPEnable, kSCPropNetProxiesFTPPort),
            (kSCPropNetProxiesSOCKSEnable, kSCPropNetProxiesSOCKSPort)
        ]

        for (enabledKey, portKey) in candidates {
            let enabled = (dictionary[enabledKey as String] as? NSNumber)?.boolValue ?? false
            let port = (dictionary[portKey as String] as? NSNumber)?.intValue ?? 0
            if enabled, port > 0 {
                ports.insert(port)
            }
        }

        return ProxySettings(ports: ports)
    }
}
