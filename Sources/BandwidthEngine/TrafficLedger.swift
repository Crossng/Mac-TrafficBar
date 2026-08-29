import Foundation

public final class TrafficLedger: @unchecked Sendable {
    private struct StoredEntry: Codable {
        var name: String
        var paths: [TrafficPath: BytePair]
    }

    private struct DayFile: Codable {
        var entries: [String: StoredEntry]
    }

    private struct RecentDelta: Codable {
        let date: Date
        let key: String
        let name: String
        let paths: [TrafficPath: BytePair]
    }

    private struct StoredNetworkUsage: Codable {
        let networkID: String
        let sessionID: String?
        var kind: NetworkKind
        var firstSeen: Date
        var lastSeen: Date
        var paths: [TrafficPath: BytePair]
    }

    private struct NetworkDayFile: Codable {
        var networks: [String: StoredNetworkUsage]
        var sessions: [String: StoredNetworkUsage]
    }

    public let storageDirectoryURL: URL
    private let calendar: Calendar
    private let lock = NSLock()
    private let recentEncoder: JSONEncoder
    private let recentDecoder: JSONDecoder
    private let recentRetentionInterval: TimeInterval
    private let recentCompactionInterval: TimeInterval
    private var recent: [RecentDelta]
    private var lastRecentCompaction: Date

    public init(
        directoryURL: URL? = nil,
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        recentRetentionInterval: TimeInterval = 3_600,
        recentCompactionInterval: TimeInterval = 600
    ) throws {
        self.calendar = calendar
        self.storageDirectoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrafficBar", isDirectory: true)
            .appendingPathComponent("engine-v3", isDirectory: true)
        self.recentEncoder = JSONEncoder()
        self.recentDecoder = JSONDecoder()
        self.recentRetentionInterval = max(recentRetentionInterval, 60)
        self.recentCompactionInterval = max(recentCompactionInterval, 0)
        self.recent = []
        self.lastRecentCompaction = referenceDate
        recentEncoder.dateEncodingStrategy = .iso8601
        recentDecoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        loadRecent(referenceDate: referenceDate)
        compactRecentFiles(referenceDate: referenceDate)
        removeStaleFiles(referenceDate: referenceDate)
    }

    public func record(
        _ deltas: [TrafficDelta],
        at date: Date = Date(),
        networkContext: NetworkContext? = nil
    ) {
        guard !deltas.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let dayID = dayIdentifier(for: date)
        var day = loadDay(dayID)
        var events: [RecentDelta] = []

        for delta in deltas {
            var entry = day.entries[delta.key] ?? StoredEntry(name: delta.name, paths: [:])
            entry.name = delta.name
            for (path, bytes) in delta.bytes {
                entry.paths[path, default: BytePair()].add(bytes)
            }
            day.entries[delta.key] = entry

            let event = RecentDelta(date: date, key: delta.key, name: delta.name, paths: delta.bytes)
            recent.append(event)
            events.append(event)
        }

        let cutoff = date.addingTimeInterval(-recentRetentionInterval)
        recent.removeAll { $0.date < cutoff }
        saveDay(day, identifier: dayID)
        if let networkContext {
            recordNetworkUsage(deltas, context: networkContext, date: date, identifier: dayID)
        }
        appendRecent(events, identifier: dayID)
        if shouldCompactRecent(at: date) {
            compactRecentFiles(referenceDate: date)
        }
        removeStaleFiles(referenceDate: date)
    }

    public func summaries(window: TimeWindow, filter: FlowFilter, at date: Date = Date()) -> [ApplicationSummary] {
        lock.lock()
        defer { lock.unlock() }

        let entries: [(String, String, [TrafficPath: BytePair])]
        switch window {
        case .hour:
            let cutoff = date.addingTimeInterval(-recentRetentionInterval)
            entries = recent
                .filter { $0.date >= cutoff && $0.date <= date }
                .map { ($0.key, $0.name, $0.paths) }
        case .today, .week, .month:
            let start = startDate(for: window, referenceDate: date)
            entries = dayIdentifiers(from: start, through: date).flatMap { identifier in
                loadDay(identifier).entries.map { ($0.key, $0.value.name, $0.value.paths) }
            }
        }

        var grouped: [String: (name: String, paths: [TrafficPath: BytePair])] = [:]
        for (key, name, paths) in entries {
            var item = grouped[key] ?? (name, [:])
            for (path, bytes) in paths {
                guard filter.includes(path) else { continue }
                item.paths[path, default: BytePair()].add(bytes)
            }
            grouped[key] = item
        }

        return grouped.map { ApplicationSummary(id: $0.key, name: $0.value.name, bytes: $0.value.paths) }
            .filter { $0.total.total > 0 }
            .sorted { lhs, rhs in
                if lhs.total.total == rhs.total.total {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.total.total > rhs.total.total
            }
    }

    public func totals(window: TimeWindow, filter: FlowFilter, at date: Date = Date()) -> BytePair {
        summaries(window: window, filter: filter, at: date)
            .reduce(into: BytePair()) { $0.add($1.total) }
    }

    public func currentSessionSummary(
        for context: NetworkContext,
        at date: Date = Date()
    ) -> NetworkUsageSummary? {
        lock.lock()
        defer { lock.unlock() }

        let retentionStart = calendar.date(byAdding: .day, value: -62, to: date) ?? date
        let requestedStart = context.connectedAt ?? calendar.startOfDay(for: date)
        let start = max(retentionStart, min(requestedStart, date))
        let records = dayIdentifiers(from: start, through: date).compactMap { identifier in
            loadNetworkDay(identifier).sessions[context.sessionID]
        }
        return aggregateNetworkUsage(records, fallbackContext: context, sessionID: context.sessionID)
    }

    public func networkSummaries(window: TimeWindow, at date: Date = Date()) -> [NetworkUsageSummary] {
        lock.lock()
        defer { lock.unlock() }

        let start = startDate(for: window, referenceDate: date)
        let records = dayIdentifiers(from: start, through: date).flatMap { identifier in
            Array(loadNetworkDay(identifier).networks.values)
        }
        let grouped = Dictionary(grouping: records, by: \.networkID)
        return grouped.compactMap { _, records in
            aggregateNetworkUsage(records, fallbackContext: nil, sessionID: nil)
        }.sorted { lhs, rhs in
            let lhsTotal = lhs.bytes.values.reduce(UInt64(0)) { $0 &+ $1.total }
            let rhsTotal = rhs.bytes.values.reduce(UInt64(0)) { $0 &+ $1.total }
            return lhsTotal > rhsTotal
        }
    }

    private func recordNetworkUsage(
        _ deltas: [TrafficDelta],
        context: NetworkContext,
        date: Date,
        identifier: String
    ) {
        var paths: [TrafficPath: BytePair] = [:]
        for delta in deltas {
            for (path, bytes) in delta.bytes {
                paths[path, default: BytePair()].add(bytes)
            }
        }
        guard paths.values.contains(where: { $0.total > 0 }) else { return }

        var day = loadNetworkDay(identifier)
        updateNetworkUsage(
            &day.networks,
            key: context.networkID,
            networkID: context.networkID,
            sessionID: nil,
            kind: context.kind,
            paths: paths,
            at: date
        )
        updateNetworkUsage(
            &day.sessions,
            key: context.sessionID,
            networkID: context.networkID,
            sessionID: context.sessionID,
            kind: context.kind,
            paths: paths,
            at: date
        )
        saveNetworkDay(day, identifier: identifier)
    }

    private func updateNetworkUsage(
        _ storage: inout [String: StoredNetworkUsage],
        key: String,
        networkID: String,
        sessionID: String?,
        kind: NetworkKind,
        paths: [TrafficPath: BytePair],
        at date: Date
    ) {
        var usage = storage[key] ?? StoredNetworkUsage(
            networkID: networkID,
            sessionID: sessionID,
            kind: kind,
            firstSeen: date,
            lastSeen: date,
            paths: [:]
        )
        usage.kind = kind
        usage.firstSeen = min(usage.firstSeen, date)
        usage.lastSeen = max(usage.lastSeen, date)
        for (path, bytes) in paths {
            usage.paths[path, default: BytePair()].add(bytes)
        }
        storage[key] = usage
    }

    private func aggregateNetworkUsage(
        _ records: [StoredNetworkUsage],
        fallbackContext: NetworkContext?,
        sessionID: String?
    ) -> NetworkUsageSummary? {
        guard let first = records.first else { return nil }
        var firstSeen = first.firstSeen
        var lastSeen = first.lastSeen
        var paths: [TrafficPath: BytePair] = [:]
        for record in records {
            firstSeen = min(firstSeen, record.firstSeen)
            lastSeen = max(lastSeen, record.lastSeen)
            for (path, bytes) in record.paths {
                paths[path, default: BytePair()].add(bytes)
            }
        }
        return NetworkUsageSummary(
            networkID: fallbackContext?.networkID ?? first.networkID,
            sessionID: sessionID,
            kind: fallbackContext?.kind ?? first.kind,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            bytes: paths
        )
    }

    private func appendRecent(_ events: [RecentDelta], identifier: String) {
        guard !events.isEmpty else { return }
        let url = recentFileURL(for: identifier)

        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .atomic)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()

        for event in events {
            guard var data = try? recentEncoder.encode(event) else { continue }
            data.append(0x0A)
            try? handle.write(contentsOf: data)
        }
    }

    private func loadRecent(referenceDate: Date) {
        let start = referenceDate.addingTimeInterval(-recentRetentionInterval)
        let cutoff = referenceDate.addingTimeInterval(-recentRetentionInterval)

        recent = dayIdentifiers(from: start, through: referenceDate).flatMap { identifier -> [RecentDelta] in
            let url = recentFileURL(for: identifier)
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }

            return text.split(whereSeparator: \.isNewline).flatMap { line -> [RecentDelta] in
                guard let data = String(line).data(using: .utf8),
                      let event = try? recentDecoder.decode(RecentDelta.self, from: data),
                      event.date >= cutoff,
                      event.date <= referenceDate else {
                    return []
                }
                return migratedRecentEvents(event)
            }
        }
    }

    private func shouldCompactRecent(at date: Date) -> Bool {
        if date < lastRecentCompaction { return true }
        return date.timeIntervalSince(lastRecentCompaction) >= recentCompactionInterval
    }

    private func compactRecentFiles(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-recentRetentionInterval)
        recent.removeAll { $0.date < cutoff || $0.date > referenceDate }

        let grouped = Dictionary(grouping: recent) { dayIdentifier(for: $0.date) }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            lastRecentCompaction = referenceDate
            return
        }

        var identifiers = Set(grouped.keys)
        for file in files where file.lastPathComponent.hasPrefix("recent-") && file.pathExtension == "jsonl" {
            identifiers.insert(String(file.deletingPathExtension().lastPathComponent.dropFirst(7)))
        }

        for identifier in identifiers {
            let url = recentFileURL(for: identifier)
            let events = (grouped[identifier] ?? []).sorted { $0.date < $1.date }

            guard !events.isEmpty else {
                try? FileManager.default.removeItem(at: url)
                continue
            }

            var data = Data()
            for event in events {
                guard var line = try? recentEncoder.encode(event) else { continue }
                line.append(0x0A)
                data.append(line)
            }
            try? data.write(to: url, options: .atomic)
        }

        lastRecentCompaction = referenceDate
    }

    private func dayIdentifier(for date: Date) -> String {
        Self.dayFormatter.string(from: calendar.startOfDay(for: date))
    }

    private func startDate(for window: TimeWindow, referenceDate: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        switch window {
        case .hour, .today:
            return startOfDay
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? startOfDay
        case .month:
            return calendar.dateInterval(of: .month, for: referenceDate)?.start ?? startOfDay
        }
    }

    private func dayIdentifiers(from start: Date, through end: Date) -> [String] {
        var output: [String] = []
        var cursor = calendar.startOfDay(for: start)
        let final = calendar.startOfDay(for: end)
        while cursor <= final {
            output.append(dayIdentifier(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }

    private func dayFileURL(for identifier: String) -> URL {
        storageDirectoryURL.appendingPathComponent("day-\(identifier).json")
    }

    private func recentFileURL(for identifier: String) -> URL {
        storageDirectoryURL.appendingPathComponent("recent-\(identifier).jsonl")
    }

    private func networkDayFileURL(for identifier: String) -> URL {
        storageDirectoryURL.appendingPathComponent("network-day-\(identifier).json")
    }

    private func loadDay(_ identifier: String) -> DayFile {
        guard let data = try? Data(contentsOf: dayFileURL(for: identifier)),
              let value = try? JSONDecoder().decode(DayFile.self, from: data) else {
            return DayFile(entries: [:])
        }
        return migratedDay(value)
    }

    private func migratedDay(_ input: DayFile) -> DayFile {
        guard let legacy = input.entries["__unattributed__"] else { return input }
        var output = input
        output.entries.removeValue(forKey: "__unattributed__")

        if let direct = legacy.paths[.direct], direct.total > 0 {
            output.entries["__unattributed_external__"] = StoredEntry(
                name: "未归属外网",
                paths: [.direct: direct]
            )
        }
        if let local = legacy.paths[.local], local.total > 0 {
            output.entries["__unattributed_local__"] = StoredEntry(
                name: "未归属本地通信",
                paths: [.local: local]
            )
        }
        return output
    }

    private func migratedRecentEvents(_ event: RecentDelta) -> [RecentDelta] {
        guard event.key == "__unattributed__" else { return [event] }
        var output: [RecentDelta] = []
        if let direct = event.paths[.direct], direct.total > 0 {
            output.append(
                RecentDelta(
                    date: event.date,
                    key: "__unattributed_external__",
                    name: "未归属外网",
                    paths: [.direct: direct]
                )
            )
        }
        if let local = event.paths[.local], local.total > 0 {
            output.append(
                RecentDelta(
                    date: event.date,
                    key: "__unattributed_local__",
                    name: "未归属本地通信",
                    paths: [.local: local]
                )
            )
        }
        return output
    }

    private func saveDay(_ day: DayFile, identifier: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(day) else { return }
        try? data.write(to: dayFileURL(for: identifier), options: .atomic)
    }

    private func loadNetworkDay(_ identifier: String) -> NetworkDayFile {
        guard let data = try? Data(contentsOf: networkDayFileURL(for: identifier)),
              let value = try? recentDecoder.decode(NetworkDayFile.self, from: data) else {
            return NetworkDayFile(networks: [:], sessions: [:])
        }
        return value
    }

    private func saveNetworkDay(_ day: NetworkDayFile, identifier: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(day) else { return }
        try? data.write(to: networkDayFileURL(for: identifier), options: .atomic)
    }

    private func removeStaleFiles(referenceDate: Date) {
        let dayCutoff = calendar.date(byAdding: .day, value: -62, to: referenceDate) ?? referenceDate
        let recentCutoff = calendar.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let cutoff: Date
            let dateText: String

            if name.hasPrefix("network-day-") {
                cutoff = dayCutoff
                dateText = String(name.dropFirst(12))
            } else if name.hasPrefix("day-") {
                cutoff = dayCutoff
                dateText = String(name.dropFirst(4))
            } else if name.hasPrefix("recent-") {
                cutoff = recentCutoff
                dateText = String(name.dropFirst(7))
            } else {
                continue
            }

            guard let fileDate = Self.dayFormatter.date(from: dateText), fileDate < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
