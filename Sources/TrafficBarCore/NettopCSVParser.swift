import Foundation

public enum NettopCSVParserError: Error, Equatable {
    case malformedConnection(String)
}

public struct NettopCSVParser: Sendable {
    public init() {}

    public func parse(_ text: String, timestamp: Date = Date()) throws -> NetworkSnapshot {
        var currentProcess: ProcessIdentity?
        var processes: [ProcessMetric] = []
        var connections: [ConnectionMetric] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else {
                continue
            }

            let entry = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty, entry != "interface" else {
                continue
            }

            if entry == "" || fields[0] == "time" {
                continue
            }

            if let process = ProcessIdentity(nettopEntry: entry) {
                currentProcess = process
                processes.append(
                    ProcessMetric(
                        process: process,
                        counter: TrafficCounter(
                            bytesIn: Self.uint64(fields[4]),
                            bytesOut: Self.uint64(fields[5])
                        )
                    )
                )
                continue
            }

            guard entry.hasPrefix("tcp") || entry.hasPrefix("udp") else {
                continue
            }

            guard let process = currentProcess else {
                continue
            }

            connections.append(
                try Self.parseConnection(entry: entry, fields: fields, process: process)
            )
        }

        return NetworkSnapshot(timestamp: timestamp, processes: processes, connections: connections)
    }

    private static func parseConnection(entry: String, fields: [String], process: ProcessIdentity) throws -> ConnectionMetric {
        let pieces = entry.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2 else {
            throw NettopCSVParserError.malformedConnection(entry)
        }

        let protocolName = String(pieces[0])
        let endpoints = pieces[1].components(separatedBy: "<->")
        guard endpoints.count == 2 else {
            throw NettopCSVParserError.malformedConnection(entry)
        }

        return ConnectionMetric(
            process: process,
            protocolName: protocolName,
            local: NetworkEndpoint(rawValue: endpoints[0]),
            remote: NetworkEndpoint(rawValue: endpoints[1]),
            interfaceName: Self.nonEmpty(fields[2]),
            state: Self.nonEmpty(fields[3]),
            counter: TrafficCounter(
                bytesIn: Self.uint64(fields[4]),
                bytesOut: Self.uint64(fields[5])
            )
        )
    }

    private static func uint64(_ text: String) -> UInt64 {
        UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
