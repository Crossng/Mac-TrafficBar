import Foundation

public struct NetworkLineParser {
    public init() {}

    public func parse(_ text: String, proxyPorts: Set<Int> = []) -> [ProcessSnapshot] {
        var current: ParsedProcess?
        var result: [ProcessSnapshot] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let columns = CSVDecoder.fields(in: line)
            guard columns.count >= 4 else { continue }

            if let identity = Self.processIdentity(from: columns[0]), columns[1].isEmpty {
                if let current {
                    result.append(current.snapshot)
                }

                let total = BytePair(
                    downloaded: Self.number(columns[2]),
                    uploaded: Self.number(columns[3])
                )
                current = ParsedProcess(identity: identity, total: total)
                continue
            }

            guard current != nil, Self.isConnectionRow(columns[0]) else { continue }
            let bytes = BytePair(
                downloaded: Self.number(columns[2]),
                uploaded: Self.number(columns[3])
            )
            guard bytes.total > 0 else { continue }

            let path = Self.path(for: columns[0], interface: columns[1], proxyPorts: proxyPorts)
            current?.add(bytes, to: path)
        }

        if let current {
            result.append(current.snapshot)
        }

        return result
    }

    private static func processIdentity(from value: String) -> (name: String, pid: Int32)? {
        guard let separator = value.lastIndex(of: "."),
              let pid = Int32(value[value.index(after: separator)...]),
              pid > 0 else {
            return nil
        }

        let name = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (name, pid)
    }

    private static func isConnectionRow(_ value: String) -> Bool {
        value.lowercased().hasPrefix("tcp") || value.lowercased().hasPrefix("udp")
    }

    private static func number(_ value: String) -> UInt64 {
        UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func path(for connection: String, interface: String, proxyPorts: Set<Int>) -> TrafficPath {
        let loweredInterface = interface.lowercased()
        let loweredConnection = connection.lowercased()

        if loweredInterface.hasPrefix("lo") || loweredConnection.contains("127.") || loweredConnection.contains("::1") {
            return .local
        }

        if loweredInterface.hasPrefix("utun") || Self.ports(in: connection).contains(where: proxyPorts.contains) {
            return .proxy
        }

        return .direct
    }

    private static func ports(in connection: String) -> [Int] {
        connection.split(whereSeparator: { $0 == ":" || $0 == "<" || $0 == ">" || $0 == "*" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

private struct ParsedProcess {
    let identity: (name: String, pid: Int32)
    let total: BytePair
    var paths: [TrafficPath: BytePair] = [:]

    var snapshot: ProcessSnapshot {
        let accounted = paths.values.reduce(into: BytePair()) { $0.add($1) }
        var output = paths
        let remainder = total.subtracting(accounted)
        if remainder.total > 0 {
            output[.direct, default: BytePair()].add(remainder)
        }
        return ProcessSnapshot(name: identity.name, pid: identity.pid, total: total, byPath: output)
    }

    mutating func add(_ bytes: BytePair, to path: TrafficPath) {
        paths[path, default: BytePair()].add(bytes)
    }
}
