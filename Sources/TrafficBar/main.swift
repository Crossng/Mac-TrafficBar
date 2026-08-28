import AppKit
import BandwidthEngine
import OSLog
import Sparkle

private enum ByteText {
    static func amount(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var number = Double(value)
        var index = 0
        while number >= 1024, index < units.count - 1 {
            number /= 1024
            index += 1
        }

        if index == 0 { return "\(Int(number)) B" }
        if number >= 100 { return String(format: "%.0f %@", number, units[index]) }
        if number >= 10 { return String(format: "%.1f %@", number, units[index]) }
        return String(format: "%.2f %@", number, units[index])
    }

    static func rate(_ value: UInt64) -> String { "\(amount(value))/s" }
}

private final class MonitorSession {
    let ledger: TrafficLedger
    let sampler = NetTopSampler()
    let calculator = DeltaCalculator()

    private var timer: Timer?
    private var sampling = false

    private(set) var rates: [String: BytePair] = [:]
    private(set) var icons: [String: NSImage] = [:]
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    var onChange: (() -> Void)?

    init() throws {
        ledger = try TrafficLedger()
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !sampling else { return }
        sampling = true
        sampler.sample { [weak self] result in
            guard let self else { return }
            self.sampling = false

            switch result {
            case let .success(networkSample):
                let now = Date()
                for snapshot in networkSample.processes {
                    if let icon = NSRunningApplication(processIdentifier: snapshot.pid)?.icon {
                        self.icons[snapshot.name] = icon
                    }
                }
                let sample = self.calculator.consume(
                    networkSample.processes,
                    interfaceTotals: networkSample.interfaceTotals,
                    proxySettings: ProxySettings.current(),
                    at: now
                )
                self.ledger.record(sample.deltas, at: now)
                self.rates = sample.rates
                self.lastUpdated = now
                self.lastError = nil
            case let .failure(error):
                self.lastError = error.localizedDescription
            }
            self.onChange?()
        }
    }

    func summaries(window: TimeWindow, filter: FlowFilter) -> [ApplicationSummary] {
        ledger.summaries(window: window, filter: filter)
    }
}

private enum PlaceholderIcon {
    private static let genericTokens: Set<String> = [
        "app", "application", "com", "daemon", "help", "helper", "io", "net", "org", "service", "xpc"
    ]

    static func image(for name: String) -> NSImage {
        let letter = monogram(for: name)
        return NSImage(size: NSSize(width: 28, height: 28), flipped: false) { bounds in
            let tileRect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let tile = NSBezierPath(roundedRect: tileRect, xRadius: 6.5, yRadius: 6.5)
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            tile.fill()
            NSColor.separatorColor.withAlphaComponent(0.72).setStroke()
            tile.lineWidth = 1
            tile.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let text = NSString(string: letter)
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: (bounds.width - textSize.width) / 2,
                    y: (bounds.height - textSize.height) / 2 - 0.5
                ),
                withAttributes: attributes
            )
            return true
        }
    }

    private static func monogram(for name: String) -> String {
        let tokens = name
            .split { character in
                character == "." || character == "-" || character == "_" || character == " " || character == "(" || character == ")"
            }
            .map(String.init)

        let candidate = tokens.reversed().first { token in
            token.count > 1 && !genericTokens.contains(token.lowercased())
        } ?? tokens.first ?? name

        guard let character = candidate.first(where: { $0.isLetter || $0.isNumber }) else {
            return "•"
        }
        return String(character).uppercased()
    }
}

private extension TrafficPath {
    var displayColor: NSColor {
        switch self {
        case .proxy: return .systemGreen
        case .direct: return .controlAccentColor
        case .local: return .systemOrange
        }
    }
}

private final class PathDistributionBar: NSView {
    private let segments: [(color: NSColor, fraction: CGFloat)]
    private let share: CGFloat

    init(summary: ApplicationSummary, maximum: UInt64) {
        let total = summary.total.total
        share = maximum > 0 ? min(1, CGFloat(Double(total) / Double(maximum))) : 0
        segments = TrafficPath.allCases.compactMap { path in
            guard let bytes = summary.bytes[path], bytes.total > 0, total > 0 else { return nil }
            return (path.displayColor, CGFloat(Double(bytes.total) / Double(total)))
        }
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.separatorColor.withAlphaComponent(0.34).setFill()
        track.fill()

        let filledWidth = bounds.width * share
        guard filledWidth > 0 else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: filledWidth, height: bounds.height),
            xRadius: radius,
            yRadius: radius
        ).addClip()

        var cursor: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            let remaining = max(0, filledWidth - cursor)
            let width = index == segments.count - 1 ? remaining : min(remaining, filledWidth * segment.fraction)
            guard width > 0 else { continue }
            segment.color.setFill()
            NSBezierPath(rect: NSRect(x: cursor, y: 0, width: width, height: bounds.height)).fill()
            cursor += width
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

private final class PathLegendView: NSView {
    init(path: TrafficPath, bytes: UInt64) {
        super.init(frame: .zero)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        dot.layer?.backgroundColor = path.displayColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "\(path.title) \(ByteText.amount(bytes))")
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = path.displayColor

        let content = NSStackView(views: [dot, label])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 5),
            dot.heightAnchor.constraint(equalToConstant: 5),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class TrafficRowView: NSView {

    init(summary: ApplicationSummary, rate: BytePair, icon: NSImage?, maximum: UInt64) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView(image: icon ?? PlaceholderIcon.image(for: summary.name))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: summary.name)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let total = NSTextField(labelWithString: ByteText.amount(summary.total.total))
        total.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        total.alignment = .right
        total.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detail = NSTextField(
            labelWithString: "下载 \(ByteText.amount(summary.total.downloaded))  上传 \(ByteText.amount(summary.total.uploaded))"
        )
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 10.5, weight: .medium)
        let live = NSTextField(labelWithString: "当前 ↓ \(ByteText.rate(rate.downloaded))  ↑ \(ByteText.rate(rate.uploaded))")
        live.textColor = .controlAccentColor
        live.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

        let top = NSStackView(views: [title, NSView(), total])
        top.orientation = .horizontal
        top.alignment = .firstBaseline
        top.spacing = 8

        let distribution = PathDistributionBar(summary: summary, maximum: maximum)
        distribution.translatesAutoresizingMaskIntoConstraints = false

        let legends = NSStackView()
        legends.orientation = .horizontal
        legends.alignment = .centerY
        legends.spacing = 6
        for path in TrafficPath.allCases {
            guard let bytes = summary.bytes[path], bytes.total > 0 else { continue }
            legends.addArrangedSubview(PathLegendView(path: path, bytes: bytes.total))
        }

        let textColumn = NSStackView(views: [top, detail, live, distribution, legends])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 4

        let row = NSStackView(views: [iconView, textColumn])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 9
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor),
            textColumn.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -37),
            top.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            detail.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            live.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            distribution.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            distribution.heightAnchor.constraint(equalToConstant: 4),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class DashboardViewController: NSViewController {
    private let session: MonitorSession
    private var windowChoice = TimeWindow.today
    private var filterChoice = FlowFilter.all

    private let updatedLabel = NSTextField(labelWithString: "")
    private let overviewCaption = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "")
    private let routeLabels = Dictionary(uniqueKeysWithValues: TrafficPath.allCases.map { ($0, NSTextField(labelWithString: "")) })
    private let rangeControl = NSSegmentedControl(labels: TimeWindow.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let filterControl = NSSegmentedControl(labels: FlowFilter.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let rows = NSStackView()
    private var rowWidthConstraints: [NSLayoutConstraint] = []
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let updater: SPUStandardUpdaterController

    init(session: MonitorSession, updater: SPUStandardUpdaterController) {
        self.session = session
        self.updater = updater
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let visual = NSVisualEffectView()
        visual.material = .popover
        visual.blendingMode = .behindWindow
        visual.state = .active
        view = visual

        let header = makeHeader()
        let overview = makeOverview()

        rangeControl.selectedSegment = TimeWindow.allCases.firstIndex(of: windowChoice) ?? 1
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))

        let controls = NSStackView(views: [rangeControl, filterControl])
        controls.orientation = .vertical
        controls.alignment = .width
        controls.spacing = 6
        controls.distribution = .fill
        rangeControl.controlSize = .small
        filterControl.controlSize = .small
        rangeControl.segmentStyle = .rounded
        filterControl.segmentStyle = .rounded
        rangeControl.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        filterControl.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        rows.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = rows
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.heightAnchor.constraint(equalToConstant: 232).isActive = true
        rows.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.stringValue = "正在等待网络数据…"
        emptyLabel.isHidden = true

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemOrange
        errorLabel.isHidden = true

        let footer = makeFooter()
        let content = NSStackView(views: [header, overview, controls, scrollView, emptyLabel, errorLabel, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(content)
        let arrangedWidth = content.widthAnchor
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            overview.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            controls.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            emptyLabel.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            errorLabel.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28),
            footer.widthAnchor.constraint(equalTo: arrangedWidth, constant: -28)
        ])

        reload()
    }

    func reload() {
        guard isViewLoaded else { return }
        let summaries = session.summaries(window: windowChoice, filter: filterChoice)
        let totals = session.ledger.totals(window: windowChoice, filter: filterChoice)
        overviewCaption.stringValue = overviewCaptionText
        totalLabel.stringValue = ByteText.amount(totals.total)
        let liveTotal = session.rates.values.reduce(into: BytePair()) { $0.add($1) }
        speedLabel.stringValue = "↓ \(ByteText.rate(liveTotal.downloaded))   ↑ \(ByteText.rate(liveTotal.uploaded))"

        for path in TrafficPath.allCases {
            let value = session.ledger.totals(window: windowChoice, filter: flowFilter(for: path))
            routeLabels[path]?.stringValue = ByteText.amount(value.total)
        }

        if let updated = session.lastUpdated {
            updatedLabel.stringValue = "更新于 \(Self.timeFormatter.string(from: updated))"
        } else {
            updatedLabel.stringValue = "正在连接系统网络统计…"
        }

        NSLayoutConstraint.deactivate(rowWidthConstraints)
        rowWidthConstraints.removeAll()
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        let maximum = summaries.first?.total.total ?? 1
        for summary in summaries.prefix(30) {
            let row = TrafficRowView(summary: summary, rate: session.rates[summary.id] ?? BytePair(), icon: icon(for: summary), maximum: maximum)
            rows.addArrangedSubview(row)
            let widthConstraint = row.widthAnchor.constraint(equalTo: rows.widthAnchor)
            rowWidthConstraints.append(widthConstraint)
            widthConstraint.isActive = true
        }
        emptyLabel.isHidden = !summaries.isEmpty

        if let error = session.lastError {
            errorLabel.stringValue = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: "流量管家")
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        speedLabel.alignment = .right
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        speedLabel.textColor = .secondaryLabelColor
        updatedLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        updatedLabel.textColor = .secondaryLabelColor
        updatedLabel.alignment = .left

        let titleStack = NSStackView(views: [title, updatedLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleStack, spacer, speedLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }

    private func makeOverview() -> NSView {
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .semibold)
        totalLabel.alignment = .left
        totalLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        overviewCaption.alignment = .left
        overviewCaption.textColor = .secondaryLabelColor
        overviewCaption.font = .systemFont(ofSize: 10.5, weight: .medium)

        let totalColumn = NSStackView(views: [overviewCaption, totalLabel])
        totalColumn.orientation = .vertical
        totalColumn.alignment = .leading
        totalColumn.spacing = 1

        let cards = NSStackView()
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.alignment = .centerY
        cards.spacing = 0
        cards.translatesAutoresizingMaskIntoConstraints = false
        for path in TrafficPath.allCases {
            let title = NSTextField(labelWithString: path.title)
            title.alignment = .left
            title.textColor = .secondaryLabelColor
            title.font = .systemFont(ofSize: 10.5, weight: .medium)

            let value = routeLabels[path]!
            value.alignment = .left
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            value.maximumNumberOfLines = 1
            value.lineBreakMode = .byClipping
            value.setContentCompressionResistancePriority(.required, for: .horizontal)

            let labels = NSStackView(views: [title, value])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 1

            let symbol = NSImageView()
            symbol.image = NSImage(
                systemSymbolName: routeSymbolName(for: path),
                accessibilityDescription: path.title
            )
            symbol.contentTintColor = .secondaryLabelColor
            symbol.imageScaling = .scaleProportionallyDown
            symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            symbol.translatesAutoresizingMaskIntoConstraints = false
            symbol.widthAnchor.constraint(equalToConstant: 14).isActive = true
            symbol.heightAnchor.constraint(equalToConstant: 14).isActive = true

            let metric = NSStackView(views: [symbol, labels])
            metric.orientation = .horizontal
            metric.alignment = .centerY
            metric.spacing = 5
            cards.addArrangedSubview(metric)
        }

        let overview = NSStackView(views: [totalColumn, cards])
        overview.orientation = .vertical
        overview.alignment = .leading
        overview.spacing = 9
        overview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cards.widthAnchor.constraint(equalTo: overview.widthAnchor)
        ])
        return overview
    }

    private var overviewCaptionText: String {
        let period: String
        switch windowChoice {
        case .hour: period = "近1小时"
        case .today: period = "今日"
        case .week: period = "本周"
        case .month: period = "本月"
        }

        let scope = filterChoice == .all ? "" : filterChoice.title
        return "\(period)\(scope)流量"
    }

    private func routeSymbolName(for path: TrafficPath) -> String {
        switch path {
        case .proxy: return "point.topleft.down.curvedto.point.bottomright.up"
        case .direct: return "arrow.triangle.branch"
        case .local: return "desktopcomputer"
        }
    }

    private func makeFooter() -> NSView {
        let refresh = iconButton(symbol: "arrow.clockwise", tip: "立即刷新", action: #selector(refreshNow))
        let updates = iconButton(symbol: "arrow.down.circle", tip: "检查更新", action: #selector(checkForUpdates))
        let folder = iconButton(symbol: "folder", tip: "打开数据目录", action: #selector(openDataFolder))
        let quit = iconButton(symbol: "power", tip: "退出", action: #selector(quit))

        let divider = NSBox()
        divider.boxType = .separator
        divider.titlePosition = .noTitle
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 14)
        ])

        let actions = NSStackView(views: [updates, refresh, folder, divider, quit])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 2
        actions.setCustomSpacing(8, after: folder)
        actions.setCustomSpacing(8, after: divider)

        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
        let version = NSTextField(labelWithString: "TrafficBar \(versionNumber)")
        version.textColor = .tertiaryLabelColor
        version.font = .systemFont(ofSize: 10.5, weight: .medium)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [version, spacer, actions])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        return footer
    }

    private func iconButton(symbol: String, tip: String, action: Selector) -> NSButton {
        let button = NSButton()
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(configuration)
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        button.bezelStyle = .inline
        button.isBordered = false
        button.controlSize = .small
        button.contentTintColor = .secondaryLabelColor
        button.focusRingType = .default
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
    }

    private func icon(for summary: ApplicationSummary) -> NSImage? {
        session.icons[summary.id]
    }

    private func flowFilter(for path: TrafficPath) -> FlowFilter {
        switch path {
        case .proxy: return .proxy
        case .direct: return .direct
        case .local: return .local
        }
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        windowChoice = TimeWindow.allCases[sender.selectedSegment]
        reload()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filterChoice = FlowFilter.allCases[sender.selectedSegment]
        reload()
    }

    @objc private func refreshNow() {
        session.refresh()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates(nil)
    }

    @objc private func openDataFolder() {
        NSWorkspace.shared.open(session.ledger.ledgerDirectoryURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension TrafficLedger {
    var ledgerDirectoryURL: URL {
        storageDirectoryURL
    }
}

private final class TrafficBarApp: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.crossng.TrafficBar", category: "startup")
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var session: MonitorSession!
    private var updater: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "流量管家")
            button.image?.isTemplate = true
            button.title = ""
            button.attributedTitle = NSAttributedString()
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "流量管家"
        }
        statusItem.isVisible = true
        log.info("status item configured, visible=\(self.statusItem.isVisible, privacy: .public)")

        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        do {
            session = try MonitorSession()
            let dashboard = DashboardViewController(session: session, updater: updater)
            popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 360, height: 500)
            popover.contentViewController = dashboard
            session.onChange = { [weak dashboard] in dashboard?.reload() }
            session.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "流量管家无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }
}

let application = NSApplication.shared
private let applicationDelegate = TrafficBarApp()
application.delegate = applicationDelegate
application.setActivationPolicy(.accessory)
application.run()
