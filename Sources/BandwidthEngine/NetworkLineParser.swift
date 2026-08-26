import Foundation

public struct NetworkLineParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> [ProcessSnapshot] {
        var current: ParsedProcess?
        var result: [ProcessSnapshot] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let columns = CSVDecoder.fields(in: line)
            guard columns.count >= 4 else { continue }

            if let identity = Self.processIdentity(from: columns[0]), columns[1].isEmpty {
                if let current { result.append(current.snapshot) }
                current = ParsedProcess(
                    identity: identity,
                    total: BytePair(
                        downloaded: Self.number(columns[2]),
                        uploaded: Self.number(columns[3])
                    )
                )
                continue
            }

            guard current != nil,
                  let connection = Self.connection(from: columns) else {
                continue
            }
            current?.connections.append(connection)
        }

        if let current { result.append(current.snapshot) }
        return result
    }

    private static func processIdentity(from value: String) -> ProcessIdentity? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("tcp"),
              !trimmed.lowercased().hasPrefix("udp"),
              let separator = trimmed.lastIndex(of: "."),
              let pid = Int32(trimmed[trimmed.index(after: separator)...]),
              pid > 0 else {
            return nil
        }

        let name = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ProcessIdentity(name: name, pid: pid)
    }

    private static func connection(from columns: [String]) -> ConnectionSnapshot? {
        let entry = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = entry.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard pieces.count == 2 else { return nil }

        let protocolName = String(pieces[0]).lowercased()
        guard protocolName.hasPrefix("tcp") || protocolName.hasPrefix("udp") else { return nil }

        let endpoints = pieces[1].components(separatedBy: "<->")
        guard endpoints.count == 2 else { return nil }

        let bytes = BytePair(
            downloaded: number(columns[2]),
            uploaded: number(columns[3])
        )

        return ConnectionSnapshot(
            identity: ConnectionIdentity(
                protocolName: protocolName,
                local: NetworkEndpoint(rawValue: endpoints[0]),
                remote: NetworkEndpoint(rawValue: endpoints[1]),
                interfaceName: columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bytes: bytes
        )
    }

    private static func number(_ value: String) -> UInt64 {
        UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

private struct ParsedProcess {
    let identity: ProcessIdentity
    let total: BytePair
    var connections: [ConnectionSnapshot] = []

    var snapshot: ProcessSnapshot {
        ProcessSnapshot(identity: identity, total: total, connections: connections)
    }
}
