import BandwidthEngine
import Darwin
import Foundation

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure(description: message) }
}

private func total(of result: SampleResult) -> BytePair {
    result.deltas.reduce(into: BytePair()) { $0.add($1.total) }
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

    let globalCapCalculator = DeltaCalculator()
    let capBaseline = [
        snapshot(
            name: "Browser", pid: 101, downloaded: 100_000, uploaded: 50_000,
            connections: [connection(local: "10.0.0.2:5001", remote: "8.8.8.8:443", interface: "en0", downloaded: 100_000, uploaded: 50_000)]
        ),
        snapshot(
            name: "Downloader", pid: 102, downloaded: 100_000, uploaded: 50_000,
            connections: [connection(local: "10.0.0.2:5002", remote: "1.1.1.1:443", interface: "en0", downloaded: 100_000, uploaded: 50_000)]
        )
    ]
    let capNext = [
        snapshot(
            name: "Browser", pid: 101, downloaded: 200_000, uploaded: 100_000,
            connections: [connection(local: "10.0.0.2:5001", remote: "8.8.8.8:443", interface: "en0", downloaded: 200_000, uploaded: 100_000)]
        ),
        snapshot(
            name: "Downloader", pid: 102, downloaded: 200_000, uploaded: 100_000,
            connections: [connection(local: "10.0.0.2:5002", remote: "1.1.1.1:443", interface: "en0", downloaded: 200_000, uploaded: 100_000)]
        )
    ]
    _ = globalCapCalculator.consume(
        capBaseline,
        interfaceTotals: ["en0": BytePair(downloaded: 1_000_000, uploaded: 1_000_000)],
        proxySettings: settings,
        at: start
    )
    let globallyCapped = globalCapCalculator.consume(
        capNext,
        interfaceTotals: ["en0": BytePair(downloaded: 1_150_000, uploaded: 1_060_000)],
        proxySettings: settings,
        at: start.addingTimeInterval(5)
    )
    try expect(
        total(of: globallyCapped) == BytePair(downloaded: 150_000, uploaded: 60_000),
        "所有进程之和不得突破物理网卡增量"
    )
    print("✓ 物理网卡全局预算守恒")

    let relayCalculator = DeltaCalculator()
    let relayBaseline = [
        snapshot(
            name: "nsurlsessiond", pid: 201, downloaded: 100_000, uploaded: 50_000,
            connections: [connection(local: "10.99.0.2:5001", remote: "8.8.8.8:443", interface: "utun9", downloaded: 100_000, uploaded: 50_000)]
        ),
        snapshot(
            name: "magicspeed-arm6", pid: 202, downloaded: 100_000, uploaded: 50_000,
            connections: [connection(local: "10.0.0.2:5002", remote: "23.141.196.52:30116", interface: "en0", downloaded: 100_000, uploaded: 50_000)]
        )
    ]
    let relayNext = [
        snapshot(
            name: "nsurlsessiond", pid: 201, downloaded: 180_000, uploaded: 70_000,
            connections: [connection(local: "10.99.0.2:5001", remote: "8.8.8.8:443", interface: "utun9", downloaded: 180_000, uploaded: 70_000)]
        ),
        snapshot(
            name: "magicspeed-arm6", pid: 202, downloaded: 184_000, uploaded: 74_000,
            connections: [connection(local: "10.0.0.2:5002", remote: "23.141.196.52:30116", interface: "en0", downloaded: 184_000, uploaded: 74_000)]
        )
    ]
    _ = relayCalculator.consume(
        relayBaseline,
        interfaceTotals: ["en0": BytePair(downloaded: 2_000_000, uploaded: 1_000_000)],
        proxySettings: settings,
        at: start
    )
    let deDuplicated = relayCalculator.consume(
        relayNext,
        interfaceTotals: ["en0": BytePair(downloaded: 2_090_000, uploaded: 1_030_000)],
        proxySettings: settings,
        at: start.addingTimeInterval(5)
    )
    try expect(total(of: deDuplicated) == BytePair(downloaded: 90_000, uploaded: 30_000), "代理去重后必须与物理网卡总量一致")
    try expect(deDuplicated.deltas.first { $0.name == "magicspeed-arm6" } == nil, "转发核心不得再次累计外网流量")
    try expect(
        deDuplicated.deltas.first { $0.name == "nsurlsessiond" }?.bytes[.proxy] == BytePair(downloaded: 80_000, uploaded: 20_000),
        "被确认的隧道客户端流量应归入代理"
    )
    try expect(
        deDuplicated.deltas.first { $0.name == "其他网络流量" }?.bytes[.direct] == BytePair(downloaded: 10_000, uploaded: 10_000),
        "未归属的协议开销应单列"
    )
    try expect(
        deDuplicated.rates["nsurlsessiond"]?[.proxy] == BytePair(downloaded: 16_000, uploaded: 4_000),
        "实时速度必须保留路径维度以匹配界面筛选"
    )
    print("✓ MagicHut/TUN 转发层重复计费消除")

    let directCoreCalculator = DeltaCalculator()
    let directCoreBaseline = snapshot(
        name: "magicspeed-arm6", pid: 301, downloaded: 100_000, uploaded: 50_000,
        connections: [connection(local: "10.0.0.2:5003", remote: "23.141.196.52:30116", interface: "en0", downloaded: 100_000, uploaded: 50_000)]
    )
    let directCoreNext = snapshot(
        name: "magicspeed-arm6", pid: 301, downloaded: 110_000, uploaded: 55_000,
        connections: [connection(local: "10.0.0.2:5003", remote: "23.141.196.52:30116", interface: "en0", downloaded: 110_000, uploaded: 55_000)]
    )
    _ = directCoreCalculator.consume(
        [directCoreBaseline],
        interfaceTotals: ["en0": BytePair(downloaded: 3_000_000, uploaded: 2_000_000)],
        proxySettings: settings,
        at: start
    )
    let directCore = directCoreCalculator.consume(
        [directCoreNext],
        interfaceTotals: ["en0": BytePair(downloaded: 3_011_000, uploaded: 2_006_000)],
        proxySettings: settings,
        at: start.addingTimeInterval(5)
    )
    try expect(
        directCore.deltas.first { $0.name == "magicspeed-arm6" }?.bytes[.direct] == BytePair(downloaded: 10_000, uploaded: 5_000),
        "没有逻辑客户端证据时不能仅凭名称隐藏流量"
    )
    print("✓ 转发核心识别防误杀")

    let unrelatedTunnelCalculator = DeltaCalculator()
    let unrelatedBaseline = [
        snapshot(
            name: "VPN Client", pid: 311, downloaded: 100_000, uploaded: 10_000,
            connections: [connection(local: "10.99.0.2:6001", remote: "8.8.4.4:443", interface: "utun12", downloaded: 100_000, uploaded: 10_000)]
        ),
        snapshot(
            name: "magicspeed-arm6", pid: 312, downloaded: 100_000, uploaded: 50_000,
            connections: [connection(local: "10.0.0.2:6002", remote: "23.141.196.52:30116", interface: "en0", downloaded: 100_000, uploaded: 50_000)]
        )
    ]
    let unrelatedNext = [
        snapshot(
            name: "VPN Client", pid: 311, downloaded: 1_100_000, uploaded: 110_000,
            connections: [connection(local: "10.99.0.2:6001", remote: "8.8.4.4:443", interface: "utun12", downloaded: 1_100_000, uploaded: 110_000)]
        ),
        snapshot(
            name: "magicspeed-arm6", pid: 312, downloaded: 105_000, uploaded: 51_000,
            connections: [connection(local: "10.0.0.2:6002", remote: "23.141.196.52:30116", interface: "en0", downloaded: 105_000, uploaded: 51_000)]
        )
    ]
    _ = unrelatedTunnelCalculator.consume(
        unrelatedBaseline,
        interfaceTotals: ["en0": BytePair(downloaded: 4_000_000, uploaded: 3_000_000)],
        proxySettings: settings,
        at: start
    )
    let unrelatedTunnel = unrelatedTunnelCalculator.consume(
        unrelatedNext,
        interfaceTotals: ["en0": BytePair(downloaded: 5_005_000, uploaded: 3_101_000)],
        proxySettings: settings,
        at: start.addingTimeInterval(5)
    )
    try expect(
        unrelatedTunnel.deltas.first { $0.name == "magicspeed-arm6" }?.bytes[.direct] == BytePair(downloaded: 5_000, uploaded: 1_000),
        "不相似的其他隧道流量不能误触发转发去重"
    )
    print("✓ 多代理并存防误判")

    let localCapCalculator = DeltaCalculator()
    let localBaseline = [
        snapshot(
            name: "Client", pid: 401, downloaded: 100_000, uploaded: 100_000,
            connections: [connection(local: "127.0.0.1:5001", remote: "127.0.0.1:6001", interface: "lo0", downloaded: 100_000, uploaded: 100_000)]
        ),
        snapshot(
            name: "Server", pid: 402, downloaded: 100_000, uploaded: 100_000,
            connections: [connection(local: "127.0.0.1:6001", remote: "127.0.0.1:5001", interface: "lo0", downloaded: 100_000, uploaded: 100_000)]
        )
    ]
    let localNext = [
        snapshot(
            name: "Client", pid: 401, downloaded: 150_000, uploaded: 150_000,
            connections: [connection(local: "127.0.0.1:5001", remote: "127.0.0.1:6001", interface: "lo0", downloaded: 150_000, uploaded: 150_000)]
        ),
        snapshot(
            name: "Server", pid: 402, downloaded: 150_000, uploaded: 150_000,
            connections: [connection(local: "127.0.0.1:6001", remote: "127.0.0.1:5001", interface: "lo0", downloaded: 150_000, uploaded: 150_000)]
        )
    ]
    _ = localCapCalculator.consume(
        localBaseline,
        interfaceTotals: ["lo0": BytePair(downloaded: 5_000_000, uploaded: 5_000_000)],
        proxySettings: settings,
        at: start
    )
    let localCapped = localCapCalculator.consume(
        localNext,
        interfaceTotals: ["lo0": BytePair(downloaded: 5_050_000, uploaded: 5_050_000)],
        proxySettings: settings,
        at: start.addingTimeInterval(5)
    )
    try expect(total(of: localCapped) == BytePair(downloaded: 50_000, uploaded: 50_000), "回环两端不得重复累计")
    print("✓ 本地回环流量去重")

    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("TrafficBarVerifier-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let ledger = try TrafficLedger(directoryURL: temporary)
    let deltas = [
        TrafficDelta(
            key: "Browser",
            name: "Browser",
            pid: 42,
            bytes: [.proxy: BytePair(downloaded: 10, uploaded: 5)]
        ),
        TrafficDelta(
            key: "Downloader",
            name: "Downloader",
            pid: 43,
            bytes: [.direct: BytePair(downloaded: 20, uploaded: 5)]
        ),
        TrafficDelta(
            key: "Local Helper",
            name: "Local Helper",
            pid: 44,
            bytes: [.local: BytePair(downloaded: 100, uploaded: 100)]
        )
    ]
    let now = Date()
    ledger.record(deltas, at: now)

    let reloaded = try TrafficLedger(directoryURL: temporary)
    try expect(
        reloaded.totals(window: .hour, filter: .external, at: now) == BytePair(downloaded: 30, uploaded: 10),
        "外网筛选必须只合并代理与直连"
    )
    try expect(
        reloaded.totals(window: .today, filter: .local, at: now) == BytePair(downloaded: 100, uploaded: 100),
        "本地通信必须独立统计"
    )
    try expect(
        reloaded.summaries(window: .today, filter: .external, at: now).allSatisfy { $0.name != "Local Helper" },
        "默认外网排行不得混入仅有本地通信的进程"
    )
    print("✓ V3 账本恢复与外网/本地语义")

    let compactDirectory = temporary.appendingPathComponent("compact", isDirectory: true)
    let calendar = Calendar.current
    let anchor = calendar.startOfDay(for: now).addingTimeInterval(12 * 3_600)
    let compactLedger = try TrafficLedger(
        directoryURL: compactDirectory,
        referenceDate: anchor,
        recentCompactionInterval: 60
    )
    func compactDelta(_ downloaded: UInt64) -> [TrafficDelta] {
        [
            TrafficDelta(
                key: "Browser",
                name: "Browser",
                pid: 42,
                bytes: [.direct: BytePair(downloaded: downloaded, uploaded: 0)]
            )
        ]
    }
    compactLedger.record(compactDelta(10), at: anchor.addingTimeInterval(-7_200))
    compactLedger.record(compactDelta(20), at: anchor.addingTimeInterval(-1_800))
    compactLedger.record(compactDelta(30), at: anchor)

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let compactRecentURL = compactDirectory
        .appendingPathComponent("recent-\(formatter.string(from: anchor)).jsonl")
    let compactText = try String(contentsOf: compactRecentURL, encoding: .utf8)
    try expect(compactText.split(whereSeparator: \.isNewline).count == 2, "最近日志应淘汰一小时前的逐次记录")

    let compactReloaded = try TrafficLedger(directoryURL: compactDirectory, referenceDate: anchor)
    try expect(
        compactReloaded.totals(window: .hour, filter: .external, at: anchor).downloaded == 50,
        "压缩后重启必须保留最近一小时统计"
    )
    try expect(
        compactReloaded.totals(window: .today, filter: .external, at: anchor).downloaded == 60,
        "压缩最近日志不得改变日汇总"
    )
    print("✓ 最近一小时日志压缩且日汇总不丢失")

    let midnightDirectory = temporary.appendingPathComponent("midnight", isDirectory: true)
    let shortlyAfterMidnight = calendar.startOfDay(for: now).addingTimeInterval(20 * 60)
    let midnightLedger = try TrafficLedger(
        directoryURL: midnightDirectory,
        referenceDate: shortlyAfterMidnight,
        recentCompactionInterval: 0
    )
    midnightLedger.record(compactDelta(40), at: shortlyAfterMidnight.addingTimeInterval(-40 * 60))
    midnightLedger.record(compactDelta(50), at: shortlyAfterMidnight)
    let midnightReloaded = try TrafficLedger(directoryURL: midnightDirectory, referenceDate: shortlyAfterMidnight)
    try expect(
        midnightReloaded.totals(window: .hour, filter: .external, at: shortlyAfterMidnight).downloaded == 90,
        "跨午夜压缩必须保留前一天最近一小时记录"
    )
    print("✓ 最近一小时日志可跨午夜恢复")
}

do {
    try runVerification()
    print("全部数据引擎验证通过")
} catch {
    fputs("验证失败：\(error)\n", stderr)
    exit(EXIT_FAILURE)
}
