import Foundation

public struct ProcessIdentity: Codable, Equatable, Hashable, Sendable {
    public let appName: String
    public let pid: Int

    public init(appName: String, pid: Int) {
        self.appName = appName
        self.pid = pid
    }

    init?(nettopEntry: String) {
        let trimmed = nettopEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("tcp"), !trimmed.hasPrefix("udp"),
              let separator = trimmed.lastIndex(of: ".") else {
            return nil
        }

        let pidText = trimmed[trimmed.index(after: separator)...]
        guard let pid = Int(pidText) else {
            return nil
        }

        let name = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }

        self.appName = name
        self.pid = pid
    }
}

public struct NetworkEndpoint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public let host: String
    public let port: Int?

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed
        let parsed = Self.parseHostAndPort(trimmed)
        self.host = parsed.host
        self.port = parsed.port
    }

    public var isLoopback: Bool {
        let lowered = host.lowercased()
        return lowered == "localhost"
            || lowered == "::1"
            || lowered == "0:0:0:0:0:0:0:1"
            || lowered.hasPrefix("127.")
    }

    public var isWildcard: Bool {
        host == "*" || host.isEmpty
    }

    private static func parseHostAndPort(_ raw: String) -> (host: String, port: Int?) {
        guard !raw.isEmpty else {
            return ("", nil)
        }

        if let colon = raw.lastIndex(of: ":") {
            let portText = raw[raw.index(after: colon)...]
            if let port = Int(portText) {
                return (String(raw[..<colon]), port)
            }
        }

        if (raw.contains(":") || raw.contains("%")),
           let dot = raw.lastIndex(of: ".") {
            let portText = raw[raw.index(after: dot)...]
            if let port = Int(portText) {
                return (String(raw[..<dot]), port)
            }
        }

        return (raw, nil)
    }
}

public enum TrafficRoute: String, Codable, CaseIterable, Sendable {
    case proxy
    case direct
    case loopback
    case unknown

    public var title: String {
        switch self {
        case .proxy:
            return "Proxy"
        case .direct:
            return "Direct"
        case .loopback:
            return "Local"
        case .unknown:
            return "Unknown"
        }
    }

    public func localizedTitle(for locale: Locale = .current) -> String {
        TrafficBarLocalization.routeTitle(self, locale: locale)
    }
}

public enum TrafficRouteFilter: String, Codable, CaseIterable, Sendable {
    case all
    case proxy
    case direct
    case loopback

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .proxy:
            return TrafficRoute.proxy.title
        case .direct:
            return TrafficRoute.direct.title
        case .loopback:
            return TrafficRoute.loopback.title
        }
    }

    public func localizedTitle(for locale: Locale = .current) -> String {
        TrafficBarLocalization.routeFilterTitle(self, locale: locale)
    }

    public var route: TrafficRoute? {
        switch self {
        case .all:
            return nil
        case .proxy:
            return .proxy
        case .direct:
            return .direct
        case .loopback:
            return .loopback
        }
    }
}

public struct TrafficCounter: Codable, Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64 = 0, bytesOut: UInt64 = 0) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var total: UInt64 {
        bytesIn + bytesOut
    }

    public mutating func add(_ other: TrafficCounter) {
        bytesIn += other.bytesIn
        bytesOut += other.bytesOut
    }

    public func delta(from previous: TrafficCounter) -> TrafficCounter? {
        guard bytesIn >= previous.bytesIn, bytesOut >= previous.bytesOut else {
            return nil
        }

        return TrafficCounter(
            bytesIn: bytesIn - previous.bytesIn,
            bytesOut: bytesOut - previous.bytesOut
        )
    }
}

public struct TrafficRate: Equatable, Sendable {
    public static let zero = TrafficRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)

    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct ProcessMetric: Codable, Equatable, Sendable {
    public let process: ProcessIdentity
    public let counter: TrafficCounter

    public init(process: ProcessIdentity, counter: TrafficCounter) {
        self.process = process
        self.counter = counter
    }

    public var appName: String {
        process.appName
    }

    public var pid: Int {
        process.pid
    }
}

public struct ConnectionMetric: Codable, Equatable, Sendable {
    public let process: ProcessIdentity
    public let protocolName: String
    public let local: NetworkEndpoint
    public let remote: NetworkEndpoint
    public let interfaceName: String?
    public let state: String?
    public let counter: TrafficCounter

    public init(
        process: ProcessIdentity,
        protocolName: String,
        local: NetworkEndpoint,
        remote: NetworkEndpoint,
        interfaceName: String?,
        state: String?,
        counter: TrafficCounter
    ) {
        self.process = process
        self.protocolName = protocolName
        self.local = local
        self.remote = remote
        self.interfaceName = interfaceName
        self.state = state
        self.counter = counter
    }

    public var bytesIn: UInt64 {
        counter.bytesIn
    }

    public var bytesOut: UInt64 {
        counter.bytesOut
    }

    public var isMeasurable: Bool {
        counter.total > 0
    }
}

public struct NetworkSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let processes: [ProcessMetric]
    public let connections: [ConnectionMetric]

    public init(timestamp: Date, processes: [ProcessMetric], connections: [ConnectionMetric]) {
        self.timestamp = timestamp
        self.processes = processes
        self.connections = connections
    }
}

public struct ProxyEndpoint: Codable, Equatable, Hashable, Sendable {
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

public struct ProxySettings: Codable, Equatable, Sendable {
    public var endpoints: Set<ProxyEndpoint>

    public init() {
        self.endpoints = []
    }

    public init<S: Sequence>(ports: S) where S.Element == Int {
        self.endpoints = Set(ports.map { ProxyEndpoint(host: nil, port: $0) })
    }

    public init(endpoints: Set<ProxyEndpoint>) {
        self.endpoints = endpoints
    }

    public var ports: Set<Int> {
        Set(endpoints.map(\.port))
    }

    public func matches(_ endpoint: NetworkEndpoint) -> Bool {
        guard let port = endpoint.port else {
            return false
        }

        let endpointHost = endpoint.host.lowercased()
        return endpoints.contains { proxy in
            guard proxy.port == port else {
                return false
            }

            if let proxyHost = proxy.host {
                return proxyHost == endpointHost
            }

            return endpoint.isLoopback
        }
    }
}

public enum StatisticsPeriod: String, Codable, CaseIterable, Sendable {
    case hour
    case day
    case week
    case month

    public var title: String {
        switch self {
        case .hour:
            return "Hour"
        case .day:
            return "Today"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }

    public func localizedTitle(for locale: Locale = .current) -> String {
        TrafficBarLocalization.periodTitle(self, locale: locale)
    }

    public func startDate(now: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        switch self {
        case .hour:
            component = .hour
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }

        return calendar.dateInterval(of: component, for: now)?.start ?? now
    }
}

public struct TrafficDelta: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let appName: String
    public let pid: Int
    public let route: TrafficRoute
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(timestamp: Date, appName: String, pid: Int, route: TrafficRoute, bytesIn: UInt64, bytesOut: UInt64) {
        self.timestamp = timestamp
        self.appName = appName
        self.pid = pid
        self.route = route
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var counter: TrafficCounter {
        TrafficCounter(bytesIn: bytesIn, bytesOut: bytesOut)
    }
}
