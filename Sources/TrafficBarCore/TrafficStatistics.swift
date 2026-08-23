import Foundation

public struct AppTrafficSummary: Equatable, Sendable {
    public let appName: String
    public private(set) var routeTotals: [TrafficRoute: TrafficCounter]

    public init(appName: String, routeTotals: [TrafficRoute: TrafficCounter] = [:]) {
        self.appName = appName
        self.routeTotals = routeTotals
    }

    public var totalBytes: UInt64 {
        routeTotals.values.reduce(UInt64(0)) { $0 + $1.total }
    }

    public mutating func add(_ delta: TrafficDelta) {
        var counter = routeTotals[delta.route] ?? TrafficCounter()
        counter.add(delta.counter)
        routeTotals[delta.route] = counter
    }
}

public enum TrafficStatistics {
    public static func aggregate(
        _ deltas: [TrafficDelta],
        period: StatisticsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AppTrafficSummary] {
        let startDate = period.startDate(now: now, calendar: calendar)
        var grouped: [String: AppTrafficSummary] = [:]

        for delta in deltas where delta.timestamp >= startDate && delta.timestamp <= now {
            var summary = grouped[delta.appName] ?? AppTrafficSummary(appName: delta.appName)
            summary.add(delta)
            grouped[delta.appName] = summary
        }

        return grouped.values.sorted {
            if $0.totalBytes == $1.totalBytes {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.totalBytes > $1.totalBytes
        }
    }

    public static func liveRates(
        from deltas: [TrafficDelta],
        elapsed: TimeInterval,
        routeFilter: TrafficRouteFilter = .all
    ) -> [String: TrafficRate] {
        guard elapsed > 0 else {
            return [:]
        }

        var countersByApp: [String: TrafficCounter] = [:]
        for delta in deltas where routeFilter.includes(delta.route) {
            var counter = countersByApp[delta.appName] ?? TrafficCounter()
            counter.add(delta.counter)
            countersByApp[delta.appName] = counter
        }

        return countersByApp.mapValues { counter in
            TrafficRate(
                downloadBytesPerSecond: Double(counter.bytesIn) / elapsed,
                uploadBytesPerSecond: Double(counter.bytesOut) / elapsed
            )
        }
    }
}

private extension TrafficRouteFilter {
    func includes(_ route: TrafficRoute) -> Bool {
        self.route.map { $0 == route } ?? true
    }
}
