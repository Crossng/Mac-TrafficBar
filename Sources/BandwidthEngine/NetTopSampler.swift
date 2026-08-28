import Darwin
import Foundation

public enum NetTopSamplerError: LocalizedError {
    case unavailable
    case timedOut
    case terminated(Int32, String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "系统网络统计工具不可用"
        case .timedOut:
            return "网络统计超时"
        case let .terminated(status, message):
            return message.isEmpty ? "网络统计失败（状态码 \(status)）" : message
        case .emptyOutput:
            return "没有读取到网络统计数据"
        }
    }
}

private final class CapturedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public final class NetTopSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.crossng.trafficbar.sampler", qos: .utility)
    private let executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
    private let parser = NetworkLineParser()
    private let interfaceSampler = InterfaceCounterSampler()
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func sample(completion: @escaping (Result<NetworkSample, Error>) -> Void) {
        queue.async { [executableURL, parser, interfaceSampler, timeout] in
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                DispatchQueue.main.async { completion(.failure(NetTopSamplerError.unavailable)) }
                return
            }

            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let didExit = DispatchSemaphore(value: 0)
            let readers = DispatchGroup()
            let output = CapturedData()
            let error = CapturedData()

            process.executableURL = executableURL
            process.arguments = ["-L", "1", "-x", "-n", "-J", "interface,bytes_in,bytes_out"]
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { _ in didExit.signal() }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                output.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }

            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                error.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }

            if didExit.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if didExit.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    didExit.wait()
                }
                readers.wait()
                DispatchQueue.main.async { completion(.failure(NetTopSamplerError.timedOut)) }
                return
            }

            readers.wait()
            let errorText = String(decoding: error.value, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard process.terminationStatus == 0 else {
                let failure = NetTopSamplerError.terminated(process.terminationStatus, errorText)
                DispatchQueue.main.async { completion(.failure(failure)) }
                return
            }

            let snapshots = parser.parse(String(decoding: output.value, as: UTF8.self))
            guard !snapshots.isEmpty else {
                DispatchQueue.main.async { completion(.failure(NetTopSamplerError.emptyOutput)) }
                return
            }

            let sample = NetworkSample(
                processes: snapshots,
                interfaceTotals: interfaceSampler.sample()
            )
            DispatchQueue.main.async { completion(.success(sample)) }
        }
    }
}
