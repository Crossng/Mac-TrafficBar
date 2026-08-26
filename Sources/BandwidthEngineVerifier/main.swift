import BandwidthEngine
import Darwin
import Foundation

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure(description: message) }
}

private func connection(
    protocolName: String = "tcp4",
    local: String,
    remote: String,
    interface: String,
    downloaded: UInt64,
    uploaded: UInt64
) -> ConnectionSnapshot {
    ConnectionSnapshot(
        identity: ConnectionIdentity(
            protocolName: protocolName,
            local: NetworkEndpoint(rawValue: local),
            remote: NetworkEndpoint(rawValue: remote),
            interfaceName: interface
        ),
        bytes: BytePair(downloaded: downloaded, uploaded: uploaded)
    )
}

private func snapshot(
    name: String = "Browser",
    pid: Int32 = 42,
    downloaded: UInt64,
    uploaded: UInt64,
    connections: [ConnectionSnapshot]
) -> ProcessSnapshot {
    ProcessSnapshot(
        identity: ProcessIdentity(name: name, pid: pid),
        total: BytePair(downloaded: downloaded, uploaded: uploaded),
        connections: connections
    )
}

private func runVerification() throws {
    let fixture = """
    ,interface,bytes_in,bytes_out,
    Browser.42,,300,100,
    tcp4 127.0.0.1:50000<->127.0.0.1:7897,lo0,100,20,
    tcp4 198.18.0.1:50001<->8.8.8.8:443,utun4,200,80,
    """
    let parsed = NetworkLineParser().parse(fixture)
    try expect(parsed.count == 1, "解析器应返回一个进程")
    try expect(parsed[0].connections.count == 2, "解析器应保留两条完整连接")

    let settings = ProxySettings(endpoints: [ProxyEndpoint(host: "127.0.0.1", port: 7897)])
    let classifier = RouteClassifier(proxySettings: settings)
    try expect(classifier.classify(parsed[0].connections[0]) == .proxy, "代理端点必须优先于回环分类")
    try expect(classifier.classify(parsed[0].connections[1]) == .direct, "utun 不能自动归类为代理")
    print("✓ 连接解析与代理分类")

    let start = Date(timeIntervalSince1970: 1_000)
    let calculator = DeltaCalculator()
    let baseline = calculator.consume(parsed, proxySettings: settings, at: start)
    try expect(baseline.deltas.isEmpty, "首次采样只能建立基线")

    let second = snapshot(
        downloaded: 350,
        uploaded: 120,
        connections: [
            connection(local: "127.0.0.1:50000", remote: "127.0.0.1:7897", interface: "lo0", downloaded: 110, uploaded: 25),
            connection(local: "198.18.0.1:50001", remote: "8.8.8.8:443", interface: "utun4", downloaded: 240, uploaded: 95)
        ]
    )
    let measured = calculator.consume([second], proxySettings: settings, at: start.addingTimeInterval(5))
    try expect(measured.deltas.count == 1, "第二次采样应产生一个进程增量")
    try expect(measured.deltas[0].bytes[.proxy] == BytePair(downloaded: 10, uploaded: 5), "代理增量计算错误")
    try expect(measured.deltas[0].bytes[.direct] == BytePair(downloaded: 40, uploaded: 15), "直连增量计算错误")
    try expect(measured.deltas[0].total == BytePair(downloaded: 50, uploaded: 20), "路径总量必须等于进程预算")
    print("✓ 首次基线与稳定连接增量")

    let restarted = DeltaCalculator().consume([second], proxySettings: settings, at: start)
    try expect(restarted.deltas.isEmpty, "重启后的首次采样不得重复写入累计值")
    print("✓ 重启不重复累计")

    let cappedCalculator = DeltaCalculator()
    let cappedFirst = snapshot(
        downloaded: 100,
        uploaded: 100,
        connections: [connection(local: "10.0.0.2:5000", remote: "8.8.8.8:443", interface: "en0", downloaded: 10, uploaded: 10)]
    )
    let cappedSecond = snapshot(
        downloaded: 105,
        uploaded: 103,
        connections: [connection(local: "10.0.0.2:5000", remote: "8.8.8.8:443", interface: "en0", downloaded: 1_000, uploaded: 1_000)]
    )
    _ = cappedCalculator.consume([cappedFirst], proxySettings: settings, at: start)
    let capped = cappedCalculator.consume([cappedSecond], proxySettings: settings, at: start.addingTimeInterval(5))
    try expect(capped.deltas[0].total == BytePair(downloaded: 5, uploaded: 3), "连接增量不得突破进程预算")
    print("✓ 进程预算硬上限")

    let churnCalculator = DeltaCalculator()
    let churnFirst = snapshot(
        downloaded: 100,
        uploaded: 50,
        connections: [connection(local: "10.0.0.2:5000", remote: "8.8.8.8:443", interface: "en0", downloaded: 100, uploaded: 50)]
    )
    let churnSecond = snapshot(
        downloaded: 140,
        uploaded: 60,
        connections: [
            connection(local: "10.0.0.2:5000", remote: "8.8.8.8:443", interface: "en0", downloaded: 110, uploaded: 55),
            connection(local: "127.0.0.1:6000", remote: "127.0.0.1:6001", interface: "lo0", downloaded: 30, uploaded: 5)
        ]
    )
    _ = churnCalculator.consume([churnFirst], proxySettings: settings, at: start)
    let churn = churnCalculator.consume([churnSecond], proxySettings: settings, at: start.addingTimeInterval(5))
    try expect(churn.deltas[0].bytes[.direct] == BytePair(downloaded: 10, uploaded: 5), "稳定连接增量应保留原路径")
    try expect(churn.deltas[0].bytes[.local] == BytePair(downloaded: 30, uploaded: 5), "新连接剩余预算应归入对应路径")
    try expect(churn.deltas[0].total == BytePair(downloaded: 40, uploaded: 10), "连接切换后总量不得重复")
    print("✓ 新连接与连接切换")

    let resetCalculator = DeltaCalculator()
    _ = resetCalculator.consume([cappedFirst], proxySettings: settings, at: start)
    let resetSnapshot = snapshot(
        downloaded: 90,
        uploaded: 110,
        connections: [connection(local: "10.0.0.2:5000", remote: "8.8.8.8:443", interface: "en0", downloaded: 5, uploaded: 20)]
    )
    let reset = resetCalculator.consume([resetSnapshot], proxySettings: settings, at: start.addingTimeInterval(5))
    try expect(reset.deltas.isEmpty, "计数器回退时必须重新建立基线")
    print("✓ PID/计数器回退保护")

    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("TrafficBarVerifier-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let ledger = try TrafficLedger(directoryURL: temporary)
    let delta = TrafficDelta(
        key: "Browser",
        name: "Browser",
        pid: 42,
        bytes: [.proxy: BytePair(downloaded: 10, uploaded: 5)]
    )
    let now = Date()
    ledger.record([delta], at: now)

    let reloaded = try TrafficLedger(directoryURL: temporary)
    try expect(reloaded.totals(window: .hour, filter: .all, at: now) == BytePair(downloaded: 10, uploaded: 5), "近一小时数据必须在重启后恢复")
    try expect(reloaded.totals(window: .today, filter: .all, at: now) == BytePair(downloaded: 10, uploaded: 5), "当天汇总必须持久化")
    print("✓ V2 小时账本跨重启恢复")
}

do {
    try runVerification()
    print("全部数据引擎验证通过")
} catch {
    fputs("验证失败：\(error)\n", stderr)
    exit(EXIT_FAILURE)
}
