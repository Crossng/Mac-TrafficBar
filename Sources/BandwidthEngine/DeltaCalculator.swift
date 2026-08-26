import Foundation

public struct SampleResult: Sendable {
    public let deltas: [TrafficDelta]
    public let rates: [String: BytePair]
    public let timestamp: Date

    public init(deltas: [TrafficDelta], rates: [String: BytePair], timestamp: Date) {
        self.deltas = deltas
        self.rates = rates
        self.timestamp = timestamp
    }
}

public final class DeltaCalculator: @unchecked Sendable {
    private struct Previous {
        let time: Date
        let total: BytePair
        let paths: [TrafficPath: BytePair]
    }

    private let lock = NSLock()
    private var previous: [String: Previous] = [:]

    public init() {}

    public func consume(_ snapshots: [ProcessSnapshot], at time: Date = Date()) -> SampleResult {
        lock.lock()
        defer { lock.unlock() }

        var deltas: [TrafficDelta] = []
        var rates: [String: BytePair] = [:]
        var activeKeys = Set<String>()

        for snapshot in snapshots {
            let key = "\(snapshot.name)#\(snapshot.pid)"
            activeKeys.insert(key)
            let old = previous[key]
            let elapsed = max(time.timeIntervalSince(old?.time ?? time), 1)
            let deltaPaths = Self.deltaPaths(current: snapshot.byPath, previous: old?.paths)
            let delta = TrafficDelta(key: snapshot.name, name: snapshot.name, pid: snapshot.pid, bytes: deltaPaths)
            if deltaPaths.values.contains(where: { $0.total > 0 }) {
                deltas.append(delta)
            }

            let rate = BytePair(
                downloaded: UInt64(Double(Self.delta(current: snapshot.total.downloaded, previous: old?.total.downloaded)) / elapsed),
                uploaded: UInt64(Double(Self.delta(current: snapshot.total.uploaded, previous: old?.total.uploaded)) / elapsed)
            )
            rates[snapshot.name, default: BytePair()].add(rate)
            previous[key] = Previous(time: time, total: snapshot.total, paths: snapshot.byPath)
        }

        previous = previous.filter { activeKeys.contains($0.key) }
        return SampleResult(deltas: deltas, rates: rates, timestamp: time)
    }

    private static func deltaPaths(current: [TrafficPath: BytePair], previous: [TrafficPath: BytePair]?) -> [TrafficPath: BytePair] {
        var output: [TrafficPath: BytePair] = [:]
        for path in TrafficPath.allCases {
            let currentValue = current[path] ?? BytePair()
            let previousValue = previous?[path] ?? BytePair()
            let value = BytePair(
                downloaded: delta(current: currentValue.downloaded, previous: previousValue.downloaded),
                uploaded: delta(current: currentValue.uploaded, previous: previousValue.uploaded)
            )
            if value.total > 0 { output[path] = value }
        }
        return output
    }

    private static func delta(current: UInt64, previous: UInt64?) -> UInt64 {
        guard let previous else { return 0 }
        return current >= previous ? current - previous : 0
    }
}
