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
    case all
    case proxy
    case direct
    case local

    public var title: String {
        switch self {
        case .all: return "全部"
        case .proxy: return "代理"
        case .direct: return "直连"
        case .local: return "本地"
        }
    }

    public var path: TrafficPath? {
        switch self {
        case .all: return nil
        case .proxy: return .proxy
        case .direct: return .direct
        case .local: return .local
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

    public func subtracting(_ other: BytePair) -> BytePair {
        BytePair(
            downloaded: downloaded >= other.downloaded ? downloaded - other.downloaded : 0,
            uploaded: uploaded >= other.uploaded ? uploaded - other.uploaded : 0
        )
    }
}

public struct ProcessSnapshot: Equatable, Sendable {
    public let name: String
    public let pid: Int32
    public let total: BytePair
    public let byPath: [TrafficPath: BytePair]

    public init(name: String, pid: Int32, total: BytePair, byPath: [TrafficPath: BytePair]) {
        self.name = name
        self.pid = pid
        self.total = total
        self.byPath = byPath
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
        bytes.values.reduce(into: BytePair()) { result, value in result.add(value) }
    }
}
