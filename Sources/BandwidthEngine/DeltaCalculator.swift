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
        let connections: [ConnectionIdentity: ConnectionSnapshot]
    }

    private let lock = NSLock()
    private var previous: [String: Previous] = [:]

    public init() {}

    public func consume(
        _ snapshots: [ProcessSnapshot],
        proxySettings: ProxySettings,
        at time: Date = Date()
    ) -> SampleResult {
        lock.lock()
        defer { lock.unlock() }

        let classifier = RouteClassifier(proxySettings: proxySettings)
        var deltas: [TrafficDelta] = []
        var rates: [String: BytePair] = [:]
        var activeKeys = Set<String>()

        for snapshot in snapshots {
            let key = snapshot.identity.key
            activeKeys.insert(key)
            let connections = mergedConnections(snapshot.connections)

            guard let old = previous[key] else {
                previous[key] = Previous(time: time, total: snapshot.total, connections: connections)
                continue
            }

            guard let processBudget = snapshot.total.delta(from: old.total) else {
                previous[key] = Previous(time: time, total: snapshot.total, connections: connections)
                continue
            }

            var remaining = processBudget
            var acceptedByPath: [TrafficPath: BytePair] = [:]
            var currentHints: [TrafficPath: BytePair] = [:]
            var fallbackHints: [TrafficPath: BytePair] = [:]

            for connection in connections.values where connection.bytes.total > 0 {
                let path = classifier.classify(connection)
                currentHints[path, default: BytePair()].add(connection.bytes)

                guard let previousConnection = old.connections[connection.identity],
                      let rawDelta = connection.bytes.delta(from: previousConnection.bytes) else {
                    fallbackHints[path, default: BytePair()].add(connection.bytes)
                    continue
                }

                let accepted = rawDelta.capped(to: remaining)
                guard accepted.total > 0 else { continue }
                acceptedByPath[path, default: BytePair()].add(accepted)
                remaining.subtract(accepted)
            }

            for (identity, oldConnection) in old.connections where connections[identity] == nil && oldConnection.bytes.total > 0 {
                let path = classifier.classify(oldConnection)
                fallbackHints[path, default: BytePair()].add(oldConnection.bytes)
            }

            if remaining.total > 0 {
                let fallbackPath = dominantPath(in: fallbackHints)
                    ?? dominantPath(in: currentHints)
                    ?? .direct
                acceptedByPath[fallbackPath, default: BytePair()].add(remaining)
            }

            let acceptedTotal = acceptedByPath.values.reduce(into: BytePair()) { $0.add($1) }
            if acceptedTotal.total > 0 {
                deltas.append(
                    TrafficDelta(
                        key: snapshot.name,
                        name: snapshot.name,
                        pid: snapshot.pid,
                        bytes: acceptedByPath
                    )
                )

                let elapsed = max(time.timeIntervalSince(old.time), 1)
                let rate = BytePair(
                    downloaded: UInt64(Double(acceptedTotal.downloaded) / elapsed),
                    uploaded: UInt64(Double(acceptedTotal.uploaded) / elapsed)
                )
                rates[snapshot.name, default: BytePair()].add(rate)
            }

            previous[key] = Previous(time: time, total: snapshot.total, connections: connections)
        }

        previous = previous.filter { activeKeys.contains($0.key) }
        return SampleResult(deltas: deltas, rates: rates, timestamp: time)
    }

    private func dominantPath(in hints: [TrafficPath: BytePair]) -> TrafficPath? {
        hints
            .filter { $0.value.total > 0 }
            .max { lhs, rhs in
                if lhs.value.total == rhs.value.total {
                    return priority(lhs.key) < priority(rhs.key)
                }
                return lhs.value.total < rhs.value.total
            }?
            .key
    }

    private func priority(_ path: TrafficPath) -> Int {
        switch path {
        case .proxy: return 3
        case .direct: return 2
        case .local: return 1
        }
    }

    private func mergedConnections(_ snapshots: [ConnectionSnapshot]) -> [ConnectionIdentity: ConnectionSnapshot] {
        var merged: [ConnectionIdentity: ConnectionSnapshot] = [:]
        for snapshot in snapshots {
            if let existing = merged[snapshot.identity] {
                var bytes = existing.bytes
                bytes.add(snapshot.bytes)
                merged[snapshot.identity] = ConnectionSnapshot(identity: snapshot.identity, bytes: bytes)
            } else {
                merged[snapshot.identity] = snapshot
            }
        }
        return merged
    }
}
