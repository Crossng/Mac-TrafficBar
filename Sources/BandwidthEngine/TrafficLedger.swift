import Foundation

public final class TrafficLedger: @unchecked Sendable {
    private struct StoredEntry: Codable {
        var name: String
        var paths: [TrafficPath: BytePair]
    }

    private struct DayFile: Codable {
        var entries: [String: StoredEntry]
    }

    private struct RecentDelta {
        let date: Date
        let key: String
        let name: String
        let paths: [TrafficPath: BytePair]
    }

    private let directoryURL: URL
    private let calendar: Calendar
    private let lock = NSLock()
    private var recent: [RecentDelta] = []

    public init(directoryURL: URL? = nil, calendar: Calendar = .current) throws {
        self.calendar = calendar
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrafficBar", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    public func record(_ deltas: [TrafficDelta], at date: Date = Date()) {
        guard !deltas.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let dayID = dayIdentifier(for: date)
        var day = loadDay(dayID)

        for delta in deltas {
            var entry = day.entries[delta.key] ?? StoredEntry(name: delta.name, paths: [:])
            entry.name = delta.name
            for (path, bytes) in delta.bytes {
                entry.paths[path, default: BytePair()].add(bytes)
            }
            day.entries[delta.key] = entry
            recent.append(RecentDelta(date: date, key: delta.key, name: delta.name, paths: delta.bytes))
        }

        recent.removeAll { $0.date < date.addingTimeInterval(-3600) }
        saveDay(day, identifier: dayID)
        removeStaleDays(olderThan: 62, referenceDate: date)
    }

    public func summaries(window: TimeWindow, filter: FlowFilter, at date: Date = Date()) -> [ApplicationSummary] {
        lock.lock()
        defer { lock.unlock() }

        let entries: [(String, String, [TrafficPath: BytePair])]
        switch window {
        case .hour:
            let cutoff = date.addingTimeInterval(-3600)
            entries = recent
                .filter { $0.date >= cutoff }
                .map { ($0.key, $0.name, $0.paths) }
        case .today, .week, .month:
            let start = startDate(for: window, referenceDate: date)
            let identifiers = dayIdentifiers(from: start, through: date)
            entries = identifiers.flatMap { identifier in
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
                if lhs.total.total == rhs.total.total { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.total.total > rhs.total.total
            }
    }

    public func totals(window: TimeWindow, filter: FlowFilter, at date: Date = Date()) -> BytePair {
        summaries(window: window, filter: filter, at: date)
            .reduce(into: BytePair()) { $0.add($1.total) }
    }

    private func dayIdentifier(for date: Date) -> String {
        Self.formatter.string(from: calendar.startOfDay(for: date))
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
            output.append(Self.formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }

    private func fileURL(for identifier: String) -> URL {
        directoryURL.appendingPathComponent("day-\(identifier).json")
    }

    private func loadDay(_ identifier: String) -> DayFile {
        guard let data = try? Data(contentsOf: fileURL(for: identifier)),
              let value = try? JSONDecoder().decode(DayFile.self, from: data) else {
            return DayFile(entries: [:])
        }
        return value
    }

    private func saveDay(_ day: DayFile, identifier: String) {
        guard let data = try? JSONEncoder.pretty.encode(day) else { return }
        try? data.write(to: fileURL(for: identifier), options: .atomic)
    }

    private func removeStaleDays(olderThan days: Int, referenceDate: Date) {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("day-") && file.pathExtension == "json" {
            guard let date = Self.dateFormatter.date(from: String(file.deletingPathExtension().lastPathComponent.dropFirst(4))) else { continue }
            if date < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateFormatter = formatter
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
