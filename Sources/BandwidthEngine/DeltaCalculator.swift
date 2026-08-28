import Foundation

public struct SampleResult: Sendable {
    public let deltas: [TrafficDelta]
    public let rates: [String: [TrafficPath: BytePair]]
    public let timestamp: Date

    public init(deltas: [TrafficDelta], rates: [String: [TrafficPath: BytePair]], timestamp: Date) {
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

    private struct RouteKey: Hashable {
        let path: TrafficPath
        let interfaceName: String
    }

    private struct Candidate {
        let processKey: String
        let name: String
        let pid: Int32
        let routes: [RouteKey: BytePair]
    }

    private struct MutableDelta {
        let key: String
        let name: String
        let pid: Int32
        var bytes: [TrafficPath: BytePair]
    }

    private struct Budgets {
        let external: BytePair?
        let local: BytePair?
    }

    private struct Component {
        let itemIndex: Int
        let path: TrafficPath
        let value: UInt64
        let orderKey: String
    }

    private let lock = NSLock()
    private var previous: [String: Previous] = [:]
    private var previousInterfaces: [String: BytePair] = [:]
    private var previousSampleTime: Date?
    private var relayEvidence: [String: Int] = [:]

    public init() {}

    public func consume(
        _ snapshots: [ProcessSnapshot],
        interfaceTotals: [String: BytePair] = [:],
        proxySettings: ProxySettings,
        at time: Date = Date()
    ) -> SampleResult {
        lock.lock()
        defer { lock.unlock() }

        let elapsed = max(time.timeIntervalSince(previousSampleTime ?? time), 1)
        previousSampleTime = time
        let budgets = updateInterfaceBudgets(interfaceTotals)
        let classifier = RouteClassifier(proxySettings: proxySettings)
        var candidates: [Candidate] = []
        var activeKeys = Set<String>()

        for snapshot in snapshots {
            let key = snapshot.identity.key
            activeKeys.insert(key)
            let connections = mergedConnections(snapshot.connections)

            guard let old = previous[key] else {
                previous[key] = Previous(time: time, total: snapshot.total, connections: connections)
                continue
            }

            defer {
                previous[key] = Previous(time: time, total: snapshot.total, connections: connections)
            }

            guard let processBudget = snapshot.total.delta(from: old.total) else { continue }

            var remaining = processBudget
            var acceptedByRoute: [RouteKey: BytePair] = [:]
            var currentHints: [RouteKey: BytePair] = [:]
            var fallbackHints: [RouteKey: BytePair] = [:]

            for connection in connections.values where connection.bytes.total > 0 {
                let route = routeKey(for: connection, classifier: classifier)
                currentHints[route, default: BytePair()].add(connection.bytes)

                guard let previousConnection = old.connections[connection.identity],
                      let rawDelta = connection.bytes.delta(from: previousConnection.bytes) else {
                    fallbackHints[route, default: BytePair()].add(connection.bytes)
                    continue
                }

                let accepted = rawDelta.capped(to: remaining)
                guard accepted.total > 0 else { continue }
                acceptedByRoute[route, default: BytePair()].add(accepted)
                remaining.subtract(accepted)
            }

            for (identity, oldConnection) in old.connections where connections[identity] == nil && oldConnection.bytes.total > 0 {
                let route = routeKey(for: oldConnection, classifier: classifier)
                fallbackHints[route, default: BytePair()].add(oldConnection.bytes)
            }

            if remaining.total > 0 {
                let fallbackRoute = dominantRoute(in: fallbackHints)
                    ?? dominantRoute(in: currentHints)
                    ?? RouteKey(path: .direct, interfaceName: "")
                acceptedByRoute[fallbackRoute, default: BytePair()].add(remaining)
            }

            guard acceptedByRoute.values.contains(where: { $0.total > 0 }) else { continue }
            candidates.append(
                Candidate(
                    processKey: key,
                    name: snapshot.name,
                    pid: snapshot.pid,
                    routes: acceptedByRoute
                )
            )
        }

        previous = previous.filter { activeKeys.contains($0.key) }
        relayEvidence = relayEvidence.filter { activeKeys.contains($0.key) }

        let relayKeys = detectedRelayKeys(in: candidates)
        let hasForwardingRelay = !relayKeys.isEmpty
        var mutable = candidates.map { candidate -> MutableDelta in
            var paths: [TrafficPath: BytePair] = [:]

            for (route, bytes) in candidate.routes where bytes.total > 0 {
                if relayKeys.contains(candidate.processKey), route.path != .local {
                    continue
                }

                let path: TrafficPath
                if hasForwardingRelay, route.path == .direct, Self.isTunnel(route.interfaceName) {
                    path = .proxy
                } else {
                    path = route.path
                }
                paths[path, default: BytePair()].add(bytes)
            }

            return MutableDelta(key: candidate.name, name: candidate.name, pid: candidate.pid, bytes: paths)
        }

        var unattributed: [TrafficPath: BytePair] = [:]
        if let externalBudget = budgets.external {
            let residual = balance(&mutable, paths: [.proxy, .direct], limit: externalBudget)
            if residual.total > 0 { unattributed[.direct] = residual }
        }
        if let localBudget = budgets.local {
            let residual = balance(&mutable, paths: [.local], limit: localBudget)
            if residual.total > 0 { unattributed[.local] = residual }
        }

        mutable = mutable.compactMap { item in
            var item = item
            item.bytes = item.bytes.filter { $0.value.total > 0 }
            return item.bytes.isEmpty ? nil : item
        }

        if !unattributed.isEmpty {
            mutable.append(
                MutableDelta(
                    key: "__unattributed__",
                    name: "其他网络流量",
                    pid: 0,
                    bytes: unattributed
                )
            )
        }

        let deltas = mutable.map {
            TrafficDelta(key: $0.key, name: $0.name, pid: $0.pid, bytes: $0.bytes)
        }
        var rates: [String: [TrafficPath: BytePair]] = [:]
        for delta in deltas {
            var pathRates = rates[delta.name] ?? [:]
            for (path, bytes) in delta.bytes {
                pathRates[path, default: BytePair()].add(
                    BytePair(
                        downloaded: UInt64(Double(bytes.downloaded) / elapsed),
                        uploaded: UInt64(Double(bytes.uploaded) / elapsed)
                    )
                )
            }
            rates[delta.name] = pathRates
        }

        return SampleResult(deltas: deltas, rates: rates, timestamp: time)
    }

    private func updateInterfaceBudgets(_ current: [String: BytePair]) -> Budgets {
        guard !current.isEmpty else { return Budgets(external: nil, local: nil) }

        var external = BytePair()
        var local = BytePair()
        var hasExternalBaseline = false
        var hasLocalBaseline = false
        var externalReset = false
        var localReset = false

        for (name, total) in current {
            if InterfaceCounterSampler.isPhysical(name) {
                guard let old = previousInterfaces[name] else { continue }
                guard let delta = total.delta(from: old) else {
                    externalReset = true
                    continue
                }
                hasExternalBaseline = true
                external.add(delta)
            } else if name == "lo0" {
                guard let old = previousInterfaces[name] else { continue }
                guard let delta = total.delta(from: old) else {
                    localReset = true
                    continue
                }
                hasLocalBaseline = true
                local.add(delta)
            }
        }

        previousInterfaces = current
        return Budgets(
            external: hasExternalBaseline && !externalReset ? external : nil,
            local: hasLocalBaseline && !localReset ? local : nil
        )
    }

    private func detectedRelayKeys(in candidates: [Candidate]) -> Set<String> {
        var logicalTraffic = BytePair()
        var logicalCandidates: [BytePair] = []
        for candidate in candidates {
            var candidateLogical = BytePair()
            for (route, bytes) in candidate.routes where route.path != .local {
                if Self.isTunnel(route.interfaceName)
                    || (route.path == .proxy && !InterfaceCounterSampler.isPhysical(route.interfaceName)) {
                    logicalTraffic.add(bytes)
                    candidateLogical.add(bytes)
                }
            }
            if candidateLogical.total > 0 { logicalCandidates.append(candidateLogical) }
        }

        guard logicalTraffic.total >= 4_096 else { return [] }
        var detected = Set<String>()

        for candidate in candidates {
            var physicalTraffic = BytePair()
            var tunnelTraffic = BytePair()
            for (route, bytes) in candidate.routes where route.path != .local {
                if InterfaceCounterSampler.isPhysical(route.interfaceName) { physicalTraffic.add(bytes) }
                if Self.isTunnel(route.interfaceName) { tunnelTraffic.add(bytes) }
            }

            guard physicalTraffic.total >= 4_096, tunnelTraffic.total == 0 else { continue }
            let knownCore = Self.isKnownRelayCore(candidate.name)
            let bestSimilarity = ([logicalTraffic] + logicalCandidates)
                .map { similarity(physicalTraffic, $0) }
                .max() ?? 0
            let resemblesForwardedTraffic = bestSimilarity >= 0.62
            let oldScore = relayEvidence[candidate.processKey] ?? 0
            let newScore = resemblesForwardedTraffic ? min(oldScore + 1, 4) : max(oldScore - 1, 0)
            relayEvidence[candidate.processKey] = newScore

            if (knownCore && bestSimilarity >= 0.35) || newScore >= 2 {
                detected.insert(candidate.processKey)
            }
        }

        return detected
    }

    private func similarity(_ lhs: BytePair, _ rhs: BytePair) -> Double {
        let lhsTotal = Double(lhs.total)
        let rhsTotal = Double(rhs.total)
        guard lhsTotal > 0, rhsTotal > 0 else { return 0 }
        let combined = min(lhsTotal, rhsTotal) / max(lhsTotal, rhsTotal)

        let directional: [Double] = [
            directionSimilarity(lhs.downloaded, rhs.downloaded),
            directionSimilarity(lhs.uploaded, rhs.uploaded)
        ].filter { $0 >= 0 }
        guard !directional.isEmpty else { return combined }
        return combined * 0.55 + directional.reduce(0, +) / Double(directional.count) * 0.45
    }

    private func directionSimilarity(_ lhs: UInt64, _ rhs: UInt64) -> Double {
        let maximum = max(lhs, rhs)
        guard maximum >= 2_048 else { return -1 }
        return Double(min(lhs, rhs)) / Double(maximum)
    }

    private func balance(
        _ items: inout [MutableDelta],
        paths: Set<TrafficPath>,
        limit: BytePair
    ) -> BytePair {
        let downloadedResidual = scale(
            &items,
            paths: paths,
            limit: limit.downloaded,
            downloaded: true
        )
        let uploadedResidual = scale(
            &items,
            paths: paths,
            limit: limit.uploaded,
            downloaded: false
        )
        return BytePair(downloaded: downloadedResidual, uploaded: uploadedResidual)
    }

    private func scale(
        _ items: inout [MutableDelta],
        paths: Set<TrafficPath>,
        limit: UInt64,
        downloaded: Bool
    ) -> UInt64 {
        var components: [Component] = []
        for itemIndex in items.indices {
            for path in paths {
                guard let pair = items[itemIndex].bytes[path] else { continue }
                let value = downloaded ? pair.downloaded : pair.uploaded
                guard value > 0 else { continue }
                components.append(
                    Component(
                        itemIndex: itemIndex,
                        path: path,
                        value: value,
                        orderKey: "\(items[itemIndex].key)|\(path.rawValue)"
                    )
                )
            }
        }

        let total = components.reduce(UInt64(0)) { $0 &+ $1.value }
        guard total > limit else { return limit - total }
        guard total > 0 else { return limit }

        let ratio = Double(limit) / Double(total)
        var allocations: [(component: Component, value: UInt64, fraction: Double)] = components.map { component in
            let exact = Double(component.value) * ratio
            return (component, UInt64(exact.rounded(.down)), exact - exact.rounded(.down))
        }
        var allocated = allocations.reduce(UInt64(0)) { $0 &+ $1.value }
        allocations.sort {
            if $0.fraction == $1.fraction { return $0.component.orderKey < $1.component.orderKey }
            return $0.fraction > $1.fraction
        }

        var index = 0
        while allocated < limit, !allocations.isEmpty {
            allocations[index].value += 1
            allocated += 1
            index = (index + 1) % allocations.count
        }

        for allocation in allocations {
            var pair = items[allocation.component.itemIndex].bytes[allocation.component.path] ?? BytePair()
            if downloaded {
                pair.downloaded = allocation.value
            } else {
                pair.uploaded = allocation.value
            }
            items[allocation.component.itemIndex].bytes[allocation.component.path] = pair
        }
        return 0
    }

    private func routeKey(for connection: ConnectionSnapshot, classifier: RouteClassifier) -> RouteKey {
        RouteKey(
            path: classifier.classify(connection),
            interfaceName: connection.identity.interfaceName.lowercased()
        )
    }

    private func dominantRoute(in hints: [RouteKey: BytePair]) -> RouteKey? {
        hints
            .filter { $0.value.total > 0 }
            .max { lhs, rhs in
                if lhs.value.total == rhs.value.total {
                    return priority(lhs.key.path) < priority(rhs.key.path)
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

    private static func isTunnel(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasPrefix("utun") || value.hasPrefix("ipsec") || value.hasPrefix("ppp")
    }

    private static func isKnownRelayCore(_ name: String) -> Bool {
        let value = name.lowercased()
        let markers = [
            "magicspeed", "mihomo", "clash", "sing-box", "singbox", "v2ray", "xray",
            "trojan-go", "hysteria", "wireguard-go", "naiveproxy", "tuic"
        ]
        return markers.contains { value.contains($0) }
    }
}
