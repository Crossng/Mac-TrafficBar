import Foundation
import SystemConfiguration

final class NetworkContextSampler: @unchecked Sendable {
    private enum DefaultsKey {
        static let networkID = "networkSession.networkID"
        static let sessionID = "networkSession.sessionID"
        static let connectedAt = "networkSession.connectedAt"
    }

    private let defaults: UserDefaults
    private var activeNetworkID: String?
    private var activeSessionID: String?
    private var activeConnectedAt: Date?
    private var unavailableSampleCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func sample() -> NetworkContext? {
        guard let global = dictionary(at: "State:/Network/Global/IPv4"),
              let interfaceName = global["PrimaryInterface"] as? String,
              !interfaceName.isEmpty else {
            noteUnavailableNetwork()
            return nil
        }

        let gateway = global["Router"] as? String
        let interface = dictionary(at: "State:/Network/Interface/\(interfaceName)/IPv4")
        let addresses = interface?["Addresses"] as? [String] ?? []
        let subnetMasks = interface?["SubnetMasks"] as? [String] ?? []
        let airport = dictionary(at: "State:/Network/Interface/\(interfaceName)/AirPort")
        let profileID = (airport?["ProfileID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let networkID: String
        if let profileID, !profileID.isEmpty {
            networkID = "wifi:\(profileID)"
        } else if let gateway, !gateway.isEmpty {
            networkID = "\(interfaceName):\(gateway)"
        } else {
            networkID = interfaceName
        }

        let session = resolveSession(for: networkID, at: Date())
        let kind = networkKind(
            interfaceName: interfaceName,
            gateway: gateway,
            addresses: addresses,
            isWiFi: profileID?.isEmpty == false || isWiFiInterface(interfaceName)
        )
        return NetworkContext(
            networkID: networkID,
            sessionID: session.id,
            interfaceName: interfaceName,
            gateway: gateway,
            addresses: addresses,
            subnetMasks: subnetMasks,
            connectedAt: session.connectedAt,
            kind: kind
        )
    }

    private func resolveSession(for networkID: String, at date: Date) -> (id: String, connectedAt: Date) {
        unavailableSampleCount = 0

        if activeNetworkID == networkID,
           let activeSessionID,
           let activeConnectedAt {
            return (activeSessionID, activeConnectedAt)
        }

        if activeNetworkID == nil,
           defaults.string(forKey: DefaultsKey.networkID) == networkID,
           let persistedSessionID = defaults.string(forKey: DefaultsKey.sessionID),
           !persistedSessionID.isEmpty {
            let timestamp = defaults.double(forKey: DefaultsKey.connectedAt)
            let persistedConnectedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : date
            activeNetworkID = networkID
            activeSessionID = persistedSessionID
            activeConnectedAt = persistedConnectedAt
            return (persistedSessionID, persistedConnectedAt)
        }

        let sessionID = "\(networkID)|session:\(UUID().uuidString.lowercased())"
        activeNetworkID = networkID
        activeSessionID = sessionID
        activeConnectedAt = date
        defaults.set(networkID, forKey: DefaultsKey.networkID)
        defaults.set(sessionID, forKey: DefaultsKey.sessionID)
        defaults.set(date.timeIntervalSince1970, forKey: DefaultsKey.connectedAt)
        return (sessionID, date)
    }

    private func noteUnavailableNetwork() {
        unavailableSampleCount += 1
        guard unavailableSampleCount >= 3 else { return }
        activeNetworkID = nil
        activeSessionID = nil
        activeConnectedAt = nil
        defaults.removeObject(forKey: DefaultsKey.networkID)
        defaults.removeObject(forKey: DefaultsKey.sessionID)
        defaults.removeObject(forKey: DefaultsKey.connectedAt)
    }

    private func dictionary(at key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any]
    }

    private func networkKind(
        interfaceName: String,
        gateway: String?,
        addresses: [String],
        isWiFi: Bool
    ) -> NetworkKind {
        if Self.isLikelyHotspot(gateway: gateway, addresses: addresses) { return .hotspot }
        if isWiFi { return .wifi }
        if interfaceName.lowercased().hasPrefix("en") { return .wired }
        return .unknown
    }

    private func isWiFiInterface(_ interfaceName: String) -> Bool {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return false
        }
        return interfaces.contains { interface in
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else {
                return false
            }
            return bsdName == interfaceName && type == (kSCNetworkInterfaceTypeIEEE80211 as String)
        }
    }

    private static func isLikelyHotspot(gateway: String?, addresses: [String]) -> Bool {
        guard let gateway else { return false }
        if gateway == "172.20.10.1", addresses.contains(where: { $0.hasPrefix("172.20.10.") }) {
            return true
        }
        if gateway == "192.168.43.1", addresses.contains(where: { $0.hasPrefix("192.168.43.") }) {
            return true
        }
        return false
    }
}
