import Darwin
import Foundation

public protocol NetworkSnapshotCollecting {
    func collect() throws -> NetworkSnapshot
}

public protocol CommandRunning: Sendable {
    func run(executablePath: String, arguments: [String]) throws -> String
}

public enum CommandRunnerError: Error, Equatable {
    case nonZeroExit(Int32, String)
    case timedOut
    case unreadableOutput
}

public struct ProcessCommandRunner: CommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let didExit = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            didExit.signal()
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let readerGroup = DispatchGroup()
        let readerQueue = DispatchQueue.global(qos: .utility)
        var output = Data()
        var error = Data()

        readerGroup.enter()
        readerQueue.async {
            output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        readerGroup.enter()
        readerQueue.async {
            error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        if didExit.wait(timeout: .now() + .milliseconds(Int(timeout * 1_000))) == .timedOut {
            process.terminate()
            if didExit.wait(timeout: .now() + .seconds(1)) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                didExit.wait()
            }
            readerGroup.wait()
            throw CommandRunnerError.timedOut
        }
        readerGroup.wait()

        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? ""
            throw CommandRunnerError.nonZeroExit(process.terminationStatus, message)
        }

        guard let text = String(data: output, encoding: .utf8) else {
            throw CommandRunnerError.unreadableOutput
        }

        return text
    }
}

public struct NettopCollector: NetworkSnapshotCollecting {
    private let runner: CommandRunning
    private let parser: NettopCSVParser

    public init(runner: CommandRunning = ProcessCommandRunner(), parser: NettopCSVParser = NettopCSVParser()) {
        self.runner = runner
        self.parser = parser
    }

    public func collect() throws -> NetworkSnapshot {
        let output = try runner.run(
            executablePath: "/usr/bin/nettop",
            arguments: ["-L", "1", "-x", "-n"]
        )
        return try parser.parse(output, timestamp: Date())
    }
}
