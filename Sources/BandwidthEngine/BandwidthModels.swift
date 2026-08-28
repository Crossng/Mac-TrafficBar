import Foundation

public enum TrafficPath: String, CaseIterable, Codable, Hashable, Sendable {
    case proxy
    case direct
    case local

    public var title: String {
        switch self {
        case .proxy: return "代理"
        case .direct: return "直连"
        case .local: return "本地"
        }
    }
}

public enum FlowFilter: String, CaseIterable, Sendable {
    case external
    case proxy
    case direct
    case local

    public var title: String {
        switch self {
        case .external: return "外网"
        case .proxy: return "代理"
        case .direct: return "直连"
        case .local: return "本地"
        }
    }

    public func includes(_ path: TrafficPath) -> Bool {
        switch self {
        case .external: return path == .proxy || path == .direct
        case .proxy: return path == .proxy
        case .direct: return path == .direct
        case .local: return path == .local
        }
    }
}

public enum TimeWindow: String, CaseIterable, Sendable {
    case hour
    case today
    case week
    case month

    public var title: String {
        switch self {
        case .hour: return "小时"
        case .today: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        }
    }
}

public struct BytePair: Codable, Equatable, Sendable {
    public var downloaded: UInt64
    public var uploaded: UInt64

    public init(downloaded: UInt64 = 0, uploaded: UInt64 = 0) {
        self.downloaded = downloaded
        self.uploaded = uploaded
    }

    public var total: UInt64 { downloaded &+ uploaded }

    public mutating func add(_ other: BytePair) {
        downloaded = downloaded &+ other.downloaded
        uploaded = uploaded &+ other.uploaded
    }

    public func delta(from previous: BytePair) -> BytePair? {
        guard downloaded >= previous.downloaded, uploaded >= previous.uploaded else {
            return nil
        }
        return BytePair(
            downloaded: downloaded - previous.downloaded,
            uploaded: uploaded - previous.uploaded
        )
    }

    public func capped(to limit: BytePair) -> BytePair {
        BytePair(
            downloaded: min(downloaded, limit.downloaded),
            uploaded: min(uploaded, limit.uploaded)
        )
    }

    public mutating func subtract(_ other: BytePair) {
        downloaded -= min(downloaded, other.downloaded)
        uploaded -= min(uploaded, other.uploaded)
    }
}

public struct ProcessIdentity: Hashable, Sendable {
    public let name: String
    public let pid: Int32

    public init(name: String, pid: Int32) {
        self.name = name
        self.pid = pid
    }

    public var key: String { "\(name)#\(pid)" }
}

public struct NetworkEndpoint: Hashable, Sendable {
    public let rawValue: String
    public let host: String
    public let port: Int?

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed
        let parsed = Self.parse(trimmed)
        self.host = parsed.host
        self.port = parsed.port
    }

    public var isLoopback: Bool {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return value == "localhost"
            || value == "::1"
            || value == "0:0:0:0:0:0:0:1"
            || value.hasPrefix("127.")
    }

    public var isWildcard: Bool { host.isEmpty || host == "*" }

    private static func parse(_ raw: String) -> (host: String, port: Int?) {
        guard !raw.isEmpty else { return ("", nil) }

        if let colon = raw.lastIndex(of: ":"),
           let port = Int(raw[raw.index(after: colon)...]) {
            return (String(raw[..<colon]), port)
        }

        if (raw.contains(":") || raw.contains("%")),
           let dot = raw.lastIndex(of: "."),
           let port = Int(raw[raw.index(after: dot)...]) {
            return (String(raw[..<dot]), port)
        }

        return (raw, nil)
    }
}

public struct ConnectionIdentity: Hashable, Sendable {
    public let protocolName: String
    public let local: NetworkEndpoint
    public let remote: NetworkEndpoint
    public let interfaceName: String

    public init(protocolName: String, local: NetworkEndpoint, remote: NetworkEndpoint, interfaceName: String) {
        self.protocolName = protocolName
        self.local = local
        self.remote = remote
        self.interfaceName = interfaceName
    }
}

public struct ConnectionSnapshot: Equatable, Sendable {
    public let identity: ConnectionIdentity
    public let bytes: BytePair

    public init(identity: ConnectionIdentity, bytes: BytePair) {
        self.identity = identity
        self.bytes = bytes
    }
}

public struct ProcessSnapshot: Equatable, Sendable {
    public let identity: ProcessIdentity
    public let total: BytePair
    public let connections: [ConnectionSnapshot]

    public init(identity: ProcessIdentity, total: BytePair, connections: [ConnectionSnapshot]) {
        self.identity = identity
        self.total = total
        self.connections = connections
    }

    public var name: String { identity.name }
    public var pid: Int32 { identity.pid }
}

public struct NetworkSample: Equatable, Sendable {
    public let processes: [ProcessSnapshot]
    public let interfaceTotals: [String: BytePair]

    public init(processes: [ProcessSnapshot], interfaceTotals: [String: BytePair]) {
        self.processes = processes
        self.interfaceTotals = interfaceTotals
    }
}

public struct TrafficDelta: Equatable, Sendable {
    public let key: String
    public let name: String
    public let pid: Int32
    public let bytes: [TrafficPath: BytePair]

    public init(key: String, name: String, pid: Int32, bytes: [TrafficPath: BytePair]) {
        self.key = key
        self.name = name
        self.pid = pid
        self.bytes = bytes
    }

    public var total: BytePair {
        bytes.values.reduce(into: BytePair()) { $0.add($1) }
    }
}

public struct ApplicationSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bytes: [TrafficPath: BytePair]

    public init(id: String, name: String, bytes: [TrafficPath: BytePair]) {
        self.id = id
        self.name = name
        self.bytes = bytes
    }

    public var total: BytePair {
        bytes.values.reduce(into: BytePair()) { $0.add($1) }
    }
}
