import Foundation

public final class JSONLinesTrafficStore {
    public let directoryURL: URL
    public let legacyFileURL: URL?
    public let retentionDays: Int
    public let loadDays: Int
    public private(set) var deltas: [TrafficDelta]

    public var fileURL: URL {
        directoryURL
    }

    private let calendar: Calendar
    private let loadedSince: Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dayFormatter: DateFormatter

    public convenience init(fileURL: URL = JSONLinesTrafficStore.defaultFileURL()) throws {
        try self.init(
            directoryURL: fileURL.deletingLastPathComponent(),
            legacyFileURL: fileURL,
            retentionDays: 90,
            loadDays: 45,
            now: Date(),
            calendar: .current
        )
    }

    public init(
        directoryURL: URL = JSONLinesTrafficStore.defaultDirectoryURL(),
        legacyFileURL: URL? = JSONLinesTrafficStore.defaultFileURL(),
        retentionDays: Int = 90,
        loadDays: Int = 45,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        self.directoryURL = directoryURL
        self.legacyFileURL = legacyFileURL
        self.retentionDays = max(1, retentionDays)
        self.loadDays = max(1, loadDays)
        self.calendar = calendar
        self.loadedSince = Self.startDate(days: max(1, loadDays), now: now, calendar: calendar)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.dayFormatter = Self.makeDayFormatter(calendar: calendar)
        self.deltas = []
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try migrateLegacyFileIfNeeded()
        try pruneExpiredShards(now: now)
        try reload()
    }

    public static func defaultDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base.appendingPathComponent("TrafficBar", isDirectory: true)
    }

    public static func defaultFileURL() -> URL {
        defaultDirectoryURL().appendingPathComponent("traffic.jsonl")
    }

    public func reload() throws {
        deltas = []

        for shard in try shardFilesToLoad() {
            deltas.append(contentsOf: try decodeDeltas(at: shard.url))
        }

        deltas.sort {
            if $0.timestamp == $1.timestamp {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.timestamp < $1.timestamp
        }
    }

    public func append(_ newDeltas: [TrafficDelta]) throws {
        guard !newDeltas.isEmpty else {
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try appendDeltasToShardFiles(newDeltas)
        deltas.append(contentsOf: newDeltas.filter { $0.timestamp >= loadedSince })
        deltas.sort {
            if $0.timestamp == $1.timestamp {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private func appendDeltasToShardFiles(_ deltas: [TrafficDelta]) throws {
        let grouped = Dictionary(grouping: deltas) { shardURL(for: $0.timestamp) }

        for (url, deltas) in grouped {
            try appendLines(deltas, to: url)
        }
    }

    private func appendLines(_ deltas: [TrafficDelta], to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()

        for delta in deltas {
            var line = try encoder.encode(delta)
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }
    }

    private func migrateLegacyFileIfNeeded() throws {
        guard let legacyFileURL,
              legacyFileURL.path != directoryURL.path,
              FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        let legacyDeltas = try decodeDeltas(at: legacyFileURL)
        if !legacyDeltas.isEmpty {
            try appendDeltasToShardFiles(legacyDeltas)
        }

        let backupURL = directoryURL.appendingPathComponent("traffic.legacy.jsonl")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.moveItem(at: legacyFileURL, to: backupURL)
    }

    private func pruneExpiredShards(now: Date) throws {
        let retentionStart = Self.startDate(days: retentionDays, now: now, calendar: calendar)

        for shard in try allShardFiles() where shard.day < retentionStart {
            try FileManager.default.removeItem(at: shard.url)
        }
    }

    private func shardFilesToLoad() throws -> [ShardFile] {
        try allShardFiles()
            .filter { $0.day >= loadedSince }
            .sorted { $0.day < $1.day }
    }

    private func allShardFiles() throws -> [ShardFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let day = dayFromShardFile(url) else {
                return nil
            }
            return ShardFile(day: day, url: url)
        }
    }

    private func decodeDeltas(at url: URL) throws -> [TrafficDelta] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(TrafficDelta.self, from: data)
            }
    }

    private func shardURL(for date: Date) -> URL {
        directoryURL.appendingPathComponent("traffic-\(dayFormatter.string(from: date)).jsonl")
    }

    private func dayFromShardFile(_ url: URL) -> Date? {
        let name = url.lastPathComponent
        guard name.hasPrefix("traffic-"),
              name.hasSuffix(".jsonl") else {
            return nil
        }

        let start = name.index(name.startIndex, offsetBy: "traffic-".count)
        let end = name.index(start, offsetBy: 10, limitedBy: name.endIndex) ?? name.endIndex
        guard end < name.endIndex else {
            return nil
        }

        return dayFormatter.date(from: String(name[start..<end]))
    }

    private static func startDate(days: Int, now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: startOfToday) ?? startOfToday
    }

    private static func makeDayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct ShardFile {
    let day: Date
    let url: URL
}
