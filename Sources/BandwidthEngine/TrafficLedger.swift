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

    public let storageDirectoryURL: URL
    private let calendar: Calendar
    private let lock = NSLock()
    private let recentEncoder: JSONEncoder
    private let recentDecoder: JSONDecoder
    private var recent: [RecentDelta]

    public init(directoryURL: URL? = nil, calendar: Calendar = .current) throws {
        self.calendar = calendar
        self.storageDirectoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrafficBar", isDirectory: true)
            .appendingPathComponent("engine-v2", isDirectory: true)
        self.recentEncoder = JSONEncoder()
        self.recentDecoder = JSONDecoder()
        self.recent = []
        recentEncoder.dateEncodingStrategy = .iso8601
        recentDecoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        loadRecent(referenceDate: Date())
        removeStaleFiles(referenceDate: Date())
    }

    public func record(_ deltas: [TrafficDelta], at date: Date = Date()) {
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

        let cutoff = date.addingTimeInterval(-3600)
        recent.removeAll { $0.date < cutoff }
        saveDay(day, identifier: dayID)
        appendRecent(events, identifier: dayID)
        removeStaleFiles(referenceDate: date)
    }

    public func summaries(window: TimeWindow, filter: FlowFilter, at date: Date = Date()) -> [ApplicationSummary] {
        lock.lock()
        defer { lock.unlock() }

        let entries: [(String, String, [TrafficPath: BytePair])]
        switch window {
        case .hour:
            let cutoff = date.addingTimeInterval(-3600)
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
                guard filter.path == nil || filter.path == path else { continue }
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
        let start = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let cutoff = referenceDate.addingTimeInterval(-3600)

        recent = dayIdentifiers(from: start, through: referenceDate).flatMap { identifier -> [RecentDelta] in
            let url = recentFileURL(for: identifier)
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }

            return text.split(whereSeparator: \.isNewline).compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let event = try? recentDecoder.decode(RecentDelta.self, from: data),
                      event.date >= cutoff,
                      event.date <= referenceDate else {
                    return nil
                }
                return event
            }
        }
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

    private func loadDay(_ identifier: String) -> DayFile {
        guard let data = try? Data(contentsOf: dayFileURL(for: identifier)),
              let value = try? JSONDecoder().decode(DayFile.self, from: data) else {
            return DayFile(entries: [:])
        }
        return value
    }

    private func saveDay(_ day: DayFile, identifier: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(day) else { return }
        try? data.write(to: dayFileURL(for: identifier), options: .atomic)
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

            if name.hasPrefix("day-") {
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
