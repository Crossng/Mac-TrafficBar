import Foundation

public enum NetTopSamplerError: LocalizedError {
    case unavailable
    case terminated(Int32, String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "系统网络统计工具不可用"
        case let .terminated(status, message):
            return message.isEmpty ? "网络统计失败（状态码 \(status)）" : message
        case .emptyOutput:
            return "没有读取到网络统计数据"
        }
    }
}

public final class NetTopSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.crossng.trafficbar.sampler", qos: .utility)
    private let executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
    private let parser = NetworkLineParser()

    public init() {}

    public func sample(completion: @escaping (Result<[ProcessSnapshot], Error>) -> Void) {
        queue.async { [executableURL, parser] in
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                DispatchQueue.main.async { completion(.failure(NetTopSamplerError.unavailable)) }
                return
            }

            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executableURL
            process.arguments = ["-L", "1", "-x", "-n", "-J", "interface,bytes_in,bytes_out"]
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = error.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: stdout, as: UTF8.self)
            let errorText = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            guard process.terminationStatus == 0 else {
                let failure = NetTopSamplerError.terminated(process.terminationStatus, errorText)
                DispatchQueue.main.async { completion(.failure(failure)) }
                return
            }

            let snapshots = parser.parse(text, proxyPorts: ProxySettings.current().ports)
            guard !snapshots.isEmpty else {
                DispatchQueue.main.async { completion(.failure(NetTopSamplerError.emptyOutput)) }
                return
            }

            DispatchQueue.main.async { completion(.success(snapshots)) }
        }
    }
}
