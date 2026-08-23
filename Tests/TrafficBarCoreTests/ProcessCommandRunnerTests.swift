import XCTest
@testable import TrafficBarCore

final class ProcessCommandRunnerTests: XCTestCase {
    func testThrowsTimeoutWhenCommandDoesNotExitInTime() {
        let runner = ProcessCommandRunner(timeout: 0.1)

        XCTAssertThrowsError(try runner.run(executablePath: "/bin/sleep", arguments: ["2"])) { error in
            XCTAssertEqual(error as? CommandRunnerError, .timedOut)
        }
    }

    func testReadsLargeOutputWithoutBlockingProcessExit() throws {
        let runner = ProcessCommandRunner(timeout: 2)

        let output = try runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "yes x | head -c 200000"]
        )

        XCTAssertEqual(output.count, 200_000)
    }
}
