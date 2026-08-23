import XCTest
@testable import TrafficBarCore

final class NettopCSVParserTests: XCTestCase {
    func testParsesProcessRowsAndConnectionRows() throws {
        let text = """
        time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
        12:00:00.100000,Safari.42,,,1000,2000,0,0,0,,,,,,,,,,,,
        12:00:00.100001,tcp4 127.0.0.1:50100<->127.0.0.1:7890,lo0,Established,300,400,0,0,0,1.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        12:00:00.100002,tcp4 192.168.1.2:50101<->93.184.216.34:443,en0,Established,700,1600,0,0,0,20.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        12:00:00.100003,ProxyApp.99,,,400,500,0,0,0,,,,,,,,,,,,
        12:00:00.100004,tcp4 127.0.0.1:7890<->127.0.0.1:50100,lo0,Established,400,500,0,0,0,1.00 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
        """

        let snapshot = try NettopCSVParser().parse(text, timestamp: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.processes.map(\.appName), ["Safari", "ProxyApp"])
        XCTAssertEqual(snapshot.processes.map(\.pid), [42, 99])
        XCTAssertEqual(snapshot.connections.count, 3)
        XCTAssertEqual(snapshot.connections[0].process.appName, "Safari")
        XCTAssertEqual(snapshot.connections[0].remote.port, 7890)
        XCTAssertEqual(snapshot.connections[1].remote.host, "93.184.216.34")
        XCTAssertEqual(snapshot.connections[1].bytesIn, 700)
        XCTAssertEqual(snapshot.connections[2].process.pid, 99)
    }
}
