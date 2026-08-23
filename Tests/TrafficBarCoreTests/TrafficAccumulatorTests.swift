import XCTest
@testable import TrafficBarCore

final class TrafficAccumulatorTests: XCTestCase {
    func testEmitsRouteDeltasAfterBaseline() throws {
        let base = Date(timeIntervalSince1970: 100)
        let proxySettings = ProxySettings(ports: [7890])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        let first = try parser.parse(Self.sample(proxyIn: 10, proxyOut: 20, directIn: 100, directOut: 200), timestamp: base)
        XCTAssertTrue(accumulator.ingest(first, proxySettings: proxySettings).isEmpty)

        let second = try parser.parse(Self.sample(proxyIn: 35, proxyOut: 90, directIn: 160, directOut: 260), timestamp: base.addingTimeInterval(5))
        let deltas = accumulator.ingest(second, proxySettings: proxySettings)

        XCTAssertEqual(deltas.count, 2)
        XCTAssertEqual(deltas.first(where: { $0.route == .proxy })?.bytesIn, 25)
        XCTAssertEqual(deltas.first(where: { $0.route == .proxy })?.bytesOut, 70)
        XCTAssertEqual(deltas.first(where: { $0.route == .direct })?.bytesIn, 60)
        XCTAssertEqual(deltas.first(where: { $0.route == .direct })?.bytesOut, 60)
    }

    func testCounterResetIsIgnoredAndRebaselined() throws {
        let proxySettings = ProxySettings(ports: [])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        _ = accumulator.ingest(try parser.parse(Self.sample(proxyIn: 0, proxyOut: 0, directIn: 1_000, directOut: 2_000), timestamp: Date(timeIntervalSince1970: 0)), proxySettings: proxySettings)
        let resetDeltas = accumulator.ingest(try parser.parse(Self.sample(proxyIn: 0, proxyOut: 0, directIn: 5, directOut: 10), timestamp: Date(timeIntervalSince1970: 5)), proxySettings: proxySettings)
        XCTAssertTrue(resetDeltas.isEmpty)

        let nextDeltas = accumulator.ingest(try parser.parse(Self.sample(proxyIn: 0, proxyOut: 0, directIn: 15, directOut: 25), timestamp: Date(timeIntervalSince1970: 10)), proxySettings: proxySettings)
        XCTAssertEqual(nextDeltas.single?.bytesIn, 10)
        XCTAssertEqual(nextDeltas.single?.bytesOut, 15)
    }

    func testFallsBackToProcessDeltasWhenConnectionKeyChanges() throws {
        let proxySettings = ProxySettings(ports: [])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        _ = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 1_000, processOut: 2_000, localPort: 50100), timestamp: Date(timeIntervalSince1970: 0)), proxySettings: proxySettings)
        let deltas = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 1_400, processOut: 2_600, localPort: 60200), timestamp: Date(timeIntervalSince1970: 5)), proxySettings: proxySettings)

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas.single?.appName, "Safari")
        XCTAssertEqual(deltas.single?.route, .direct)
        XCTAssertEqual(deltas.single?.bytesIn, 400)
        XCTAssertEqual(deltas.single?.bytesOut, 600)
    }

    func testSuppressesRepeatedFallbackWhenConnectionKeyChangesButCounterIsUnchanged() throws {
        let proxySettings = ProxySettings(ports: [])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        _ = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 69_000_000, processOut: 0, connectionIn: 69_000_000, connectionOut: 0, localPort: 50100), timestamp: Date(timeIntervalSince1970: 0)), proxySettings: proxySettings)
        let deltas = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 138_000_000, processOut: 0, connectionIn: 69_000_000, connectionOut: 0, localPort: 60200), timestamp: Date(timeIntervalSince1970: 5)), proxySettings: proxySettings)

        XCTAssertTrue(deltas.isEmpty)
    }

    func testSuppressesConnectionDeltaWhenProcessCounterIsUnchanged() throws {
        let proxySettings = ProxySettings(ports: [])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        _ = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 166_274_541, processOut: 537_072, connectionIn: 69_926_611, connectionOut: 0, localPort: 50100), timestamp: Date(timeIntervalSince1970: 0)), proxySettings: proxySettings)
        let deltas = accumulator.ingest(try parser.parse(Self.processSample(pid: 42, processIn: 166_274_541, processOut: 537_072, connectionIn: 139_853_222, connectionOut: 0, localPort: 50100), timestamp: Date(timeIntervalSince1970: 5)), proxySettings: proxySettings)

        XCTAssertTrue(deltas.isEmpty)
    }

    func testFallsBackToUnknownProcessDeltaWithoutConnections() throws {
        let proxySettings = ProxySettings(ports: [])
        let parser = NettopCSVParser()
        var accumulator = TrafficAccumulator()

        _ = accumulator.ingest(try parser.parse(Self.processOnlySample(processIn: 5_000, processOut: 6_000), timestamp: Date(timeIntervalSince1970: 0)), proxySettings: proxySettings)
        let deltas = accumulator.ingest(try parser.parse(Self.processOnlySample(processIn: 5_300, processOut: 6_700), timestamp: Date(timeIntervalSince1970: 5)), proxySettings: proxySettings)

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas.single?.route, .unknown)
        XCTAssertEqual(deltas.single?.bytesIn, 300)
        XCTAssertEqual(deltas.single?.bytesOut, 700)
    }

    private static func sample(proxyIn: UInt64, proxyOut: UInt64, directIn: UInt64, directOut: UInt64) -> String {
        """
        time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
        12:00:00.100000,Safari.42,,,0,0,0,0,0,,,,,,,,,,,,
        12:00:00.100001,tcp4 127.0.0.1:50100<->127.0.0.1:7890,lo0,Established,\(proxyIn),\(proxyOut),0,0,0,1.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        12:00:00.100002,tcp4 192.168.1.2:50101<->93.184.216.34:443,en0,Established,\(directIn),\(directOut),0,0,0,20.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        """
    }

    private static func processSample(pid: Int, processIn: UInt64, processOut: UInt64, localPort: Int) -> String {
        processSample(
            pid: pid,
            processIn: processIn,
            processOut: processOut,
            connectionIn: processIn,
            connectionOut: processOut,
            localPort: localPort
        )
    }

    private static func processSample(pid: Int, processIn: UInt64, processOut: UInt64, connectionIn: UInt64, connectionOut: UInt64, localPort: Int) -> String {
        """
        time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
        12:00:00.100000,Safari.\(pid),,,\(processIn),\(processOut),0,0,0,,,,,,,,,,,,
        12:00:00.100001,tcp4 192.168.1.2:\(localPort)<->93.184.216.34:443,en0,Established,\(connectionIn),\(connectionOut),0,0,0,20.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        """
    }

    private static func processOnlySample(processIn: UInt64, processOut: UInt64) -> String {
        """
        time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
        12:00:00.100000,Safari.42,,,\(processIn),\(processOut),0,0,0,,,,,,,,,,,,
        """
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
