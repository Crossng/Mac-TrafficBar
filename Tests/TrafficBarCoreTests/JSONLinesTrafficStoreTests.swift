import XCTest
@testable import TrafficBarCore

final class JSONLinesTrafficStoreTests: XCTestCase {
    func testAppendWritesDailyShardFiles() throws {
        let fixture = StoreFixture()
        let store = try JSONLinesTrafficStore(
            directoryURL: fixture.directoryURL,
            legacyFileURL: nil,
            retentionDays: 90,
            loadDays: 45,
            now: fixture.date("2026-05-07T12:00:00Z"),
            calendar: fixture.calendar
        )

        try store.append([
            fixture.delta("Safari", at: "2026-05-07T12:00:00Z"),
            fixture.delta("Code", at: "2026-05-06T23:00:00Z")
        ])

        XCTAssertTrue(fixture.exists("traffic-2026-05-07.jsonl"))
        XCTAssertTrue(fixture.exists("traffic-2026-05-06.jsonl"))
        XCTAssertFalse(fixture.exists("traffic.jsonl"))
        XCTAssertEqual(store.deltas.map(\.appName), ["Code", "Safari"])
    }

    func testReloadLoadsOnlyRecentShardWindow() throws {
        let fixture = StoreFixture()
        try fixture.writeShard("2026-05-07", delta: fixture.delta("Today", at: "2026-05-07T12:00:00Z"))
        try fixture.writeShard("2026-05-06", delta: fixture.delta("Yesterday", at: "2026-05-06T12:00:00Z"))
        try fixture.writeShard("2026-05-04", delta: fixture.delta("Old", at: "2026-05-04T12:00:00Z"))

        let store = try JSONLinesTrafficStore(
            directoryURL: fixture.directoryURL,
            legacyFileURL: nil,
            retentionDays: 90,
            loadDays: 2,
            now: fixture.date("2026-05-07T18:00:00Z"),
            calendar: fixture.calendar
        )

        XCTAssertEqual(store.deltas.map(\.appName), ["Yesterday", "Today"])
    }

    func testPrunesExpiredShardFiles() throws {
        let fixture = StoreFixture()
        try fixture.writeShard("2026-05-07", delta: fixture.delta("Today", at: "2026-05-07T12:00:00Z"))
        try fixture.writeShard("2026-05-05", delta: fixture.delta("Kept", at: "2026-05-05T12:00:00Z"))
        try fixture.writeShard("2026-05-04", delta: fixture.delta("Expired", at: "2026-05-04T12:00:00Z"))
        try "keep me".write(to: fixture.url("notes.txt"), atomically: true, encoding: .utf8)

        _ = try JSONLinesTrafficStore(
            directoryURL: fixture.directoryURL,
            legacyFileURL: nil,
            retentionDays: 3,
            loadDays: 3,
            now: fixture.date("2026-05-07T18:00:00Z"),
            calendar: fixture.calendar
        )

        XCTAssertTrue(fixture.exists("traffic-2026-05-07.jsonl"))
        XCTAssertTrue(fixture.exists("traffic-2026-05-05.jsonl"))
        XCTAssertFalse(fixture.exists("traffic-2026-05-04.jsonl"))
        XCTAssertTrue(fixture.exists("notes.txt"))
    }

    func testMigratesLegacySingleFileIntoDailyShardsOnce() throws {
        let fixture = StoreFixture()
        let legacyURL = fixture.url("traffic.jsonl")
        try fixture.writeLines([fixture.delta("Legacy", at: "2026-05-07T12:00:00Z")], to: legacyURL)

        let store = try JSONLinesTrafficStore(
            directoryURL: fixture.directoryURL,
            legacyFileURL: legacyURL,
            retentionDays: 90,
            loadDays: 45,
            now: fixture.date("2026-05-07T18:00:00Z"),
            calendar: fixture.calendar
        )

        XCTAssertEqual(store.deltas.map(\.appName), ["Legacy"])
        XCTAssertTrue(fixture.exists("traffic-2026-05-07.jsonl"))
        XCTAssertFalse(fixture.exists("traffic.jsonl"))
        XCTAssertTrue(fixture.exists("traffic.legacy.jsonl"))
    }
}

private final class StoreFixture {
    let directoryURL: URL
    let calendar: Calendar
    private let encoder: JSONEncoder
    private let formatter: ISO8601DateFormatter

    init(file: StaticString = #filePath, line: UInt = #line) {
        self.directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrafficBarStoreTests-\(UUID().uuidString)", isDirectory: true)
        self.encoder = JSONEncoder()
        self.formatter = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        encoder.dateEncodingStrategy = .iso8601

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temp directory: \(error)", file: file, line: line)
        }
    }

    func date(_ text: String) -> Date {
        formatter.date(from: text)!
    }

    func delta(_ appName: String, at timestamp: String) -> TrafficDelta {
        TrafficDelta(
            timestamp: date(timestamp),
            appName: appName,
            pid: 1,
            route: .direct,
            bytesIn: 10,
            bytesOut: 5
        )
    }

    func url(_ name: String) -> URL {
        directoryURL.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    func writeShard(_ day: String, delta: TrafficDelta) throws {
        try writeLines([delta], to: url("traffic-\(day).jsonl"))
    }

    func writeLines(_ deltas: [TrafficDelta], to url: URL) throws {
        var data = Data()
        for delta in deltas {
            data.append(try encoder.encode(delta))
            data.append(0x0A)
        }
        try data.write(to: url)
    }
}
