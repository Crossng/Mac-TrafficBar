import XCTest
@testable import BandwidthEngine

final class NetworkLineParserTests: XCTestCase {
    func testGroupsConnectionBytesByRoute() {
        let text = """
        ,interface,bytes_in,bytes_out,
        Demo App.12,,300,100,
        tcp4 127.0.0.1:5000<->127.0.0.1:5001,lo0,100,20,
        tcp4 10.0.0.1:5000<->10.0.0.2:443,en0,200,80,
        """

        let result = NetworkLineParser().parse(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].total, BytePair(downloaded: 300, uploaded: 100))
        XCTAssertEqual(result[0].byPath[.local], BytePair(downloaded: 100, uploaded: 20))
        XCTAssertEqual(result[0].byPath[.direct], BytePair(downloaded: 200, uploaded: 80))
    }

    func testProxyPortIsRecognized() {
        let text = """
        ,interface,bytes_in,bytes_out,
        Browser.9,,40,20,
        tcp4 10.0.0.1:5000<->10.0.0.2:7890,en0,40,20,
        """

        let result = NetworkLineParser().parse(text, proxyPorts: [7890])
        XCTAssertEqual(result[0].byPath[.proxy], BytePair(downloaded: 40, uploaded: 20))
    }
}
