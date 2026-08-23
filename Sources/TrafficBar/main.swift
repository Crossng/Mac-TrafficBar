import AppKit
import TrafficBarCore
import Sparkle
import UniformTypeIdentifiers

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController()
        controller?.start()
    }
}

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: MonitorModel
    private let dashboardController: DashboardViewController
    private let statusRateView = StatusRateView()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        self.model = MonitorModel()
        self.dashboardController = DashboardViewController()
        super.init()

        dashboardController.onPeriodChange = { [weak self] period in
            self?.model.period = period
        }
        dashboardController.onRouteFilterChange = { [weak self] routeFilter in
            self?.model.routeFilter = routeFilter
        }
        dashboardController.onRefresh = { [weak self] in
            self?.model.tick()
        }
        dashboardController.onOpenDataFolder = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.model.storeFileURL])
        }
        dashboardController.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        dashboardController.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        model.onChange = { [weak self] in
            self?.render()
        }
    }

    func start() {
        configureStatusItem()
        configurePopover()
        _ = updaterController
        render()
        model.start()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        // Keep the menu-bar entry visible even when the menu bar is crowded.
        // The detailed live rates remain available in the popover dashboard.
        statusItem.length = NSStatusItem.squareLength
        button.image = NSImage(
            systemSymbolName: "arrow.up.arrow.down.circle",
            accessibilityDescription: TrafficBarLocalization.productName
        )
        button.image?.isTemplate = true
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "\(TrafficBarLocalization.productName) \(AppVersion.current.tagString)"
    }

    private func configurePopover() {
        popover.behavior = .transient
        let layout = TrafficPresentation.dashboardLayout
        popover.contentSize = NSSize(width: layout.popoverWidth, height: layout.popoverHeight)
        popover.contentViewController = dashboardController
        _ = dashboardController.view
    }

    private func render() {
        applyStatusTitle(model.statusTitle)
        dashboardController.update(
            dashboard: model.dashboard,
            period: model.period,
            routeFilter: model.routeFilter,
            lastUpdated: model.lastUpdated,
            lastError: model.lastError,
            downloadRate: model.lastDownloadBytesPerSecond,
            uploadRate: model.lastUploadBytesPerSecond
        )
    }

    private func applyStatusTitle(_ title: String) {
        guard let button = statusItem.button else {
            return
        }

        statusRateView.title = title
        button.toolTip = "\(TrafficBarLocalization.productName) \(AppVersion.current.tagString)  \(title.replacingOccurrences(of: "\n", with: "  "))"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func checkForUpdates() {
        popover.performClose(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            render()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            dashboardController.view.window?.makeKey()
        }
    }
}

final class StatusRateView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let layout = TrafficPresentation.statusBarRateLayout

    var title: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.attributedStringValue = StatusRateView.attributedTitle(newValue, lineHeight: CGFloat(layout.lineHeight))
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: CGFloat(layout.statusItemWidth - 8),
            height: CGFloat(max(layout.minimumItemHeight, layout.contentHeight))
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func setup() {
        wantsLayer = false

        iconView.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: TrafficBarLocalization.productName)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: CGFloat(layout.iconSize), weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byClipping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CGFloat(layout.horizontalPadding)),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: CGFloat(layout.iconSize)),
            iconView.heightAnchor.constraint(equalToConstant: CGFloat(layout.iconSize)),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: CGFloat(layout.spacing)),
            titleLabel.widthAnchor.constraint(equalToConstant: CGFloat(layout.textColumnWidth)),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -CGFloat(layout.horizontalPadding)),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: CGFloat(layout.textBlockHeight))
        ])
    }

    private static func attributedTitle(_ title: String, lineHeight: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineSpacing = 0

        return NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.4, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
                .baselineOffset: -0.5
            ]
        )
    }
}

final class DashboardViewController: NSViewController {
    var onPeriodChange: ((StatisticsPeriod) -> Void)?
    var onRouteFilterChange: ((TrafficRouteFilter) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenDataFolder: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private let layout = TrafficPresentation.dashboardLayout
    private let iconProvider = AppIconProvider()
    private let titleLabel = Label(style: .title)
    private let statusLabel = Label(style: .caption)
    private let rateLabel = Label(style: .caption)
    private let totalValueLabel = Label(style: .headline)
    private let totalCaptionLabel = Label(style: .caption)
    private let proxyMetric = MetricPillView(title: TrafficRoute.proxy.localizedTitle(), symbolName: "point.topleft.down.curvedto.point.bottomright.up")
    private let directMetric = MetricPillView(title: TrafficRoute.direct.localizedTitle(), symbolName: "arrow.triangle.branch")
    private let loopbackMetric = MetricPillView(title: TrafficRoute.loopback.localizedTitle(), symbolName: "desktopcomputer")
    private let periodControl = NSSegmentedControl(labels: StatisticsPeriod.allCases.map { $0.localizedTitle() }, trackingMode: .selectOne, target: nil, action: nil)
    private let routeControl = NSSegmentedControl(labels: TrafficRouteFilter.allCases.map { $0.localizedTitle() }, trackingMode: .selectOne, target: nil, action: nil)
    private let rowStack = NSStackView()
    private let emptyState = Label(style: .body)
    private let scrollView = NSScrollView()
    private var rowWidthConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: layout.popoverWidth, height: layout.popoverHeight)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(effectView)

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = CGFloat(layout.sectionSpacing)
        rootStack.edgeInsets = NSEdgeInsets(
            top: CGFloat(layout.contentPadding),
            left: CGFloat(layout.contentPadding),
            bottom: CGFloat(layout.contentPadding),
            right: CGFloat(layout.contentPadding)
        )
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(rootStack)

        rootStack.addArrangedSubview(headerView())
        rootStack.addArrangedSubview(totalBand())
        rootStack.addArrangedSubview(filterView())
        rootStack.addArrangedSubview(listView())
        rootStack.addArrangedSubview(footerView())

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rootStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: effectView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            headerViewWidthConstraint(rootStack),
            totalBandWidthConstraint(rootStack),
            filterViewWidthConstraint(rootStack),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -CGFloat(layout.contentPadding * 2)),
            scrollView.heightAnchor.constraint(equalToConstant: CGFloat(layout.scrollHeight)),
            footerWidthConstraint(rootStack)
        ])
    }

    func update(
        dashboard: TrafficDashboardPresentation,
        period: StatisticsPeriod,
        routeFilter: TrafficRouteFilter,
        lastUpdated: Date?,
        lastError: String?,
        downloadRate: Double,
        uploadRate: Double
    ) {
        titleLabel.stringValue = TrafficBarLocalization.productName
        rateLabel.stringValue = TrafficPresentation.rateLabel(
            downloadBytesPerSecond: downloadRate,
            uploadBytesPerSecond: uploadRate
        )
        totalValueLabel.stringValue = dashboard.totalLabel
        totalCaptionLabel.stringValue = Self.totalCaption(periodTitle: dashboard.periodTitle, routeFilter: routeFilter)
        proxyMetric.value = dashboard.proxyLabel
        directMetric.value = dashboard.directLabel
        loopbackMetric.value = dashboard.loopbackLabel
        emptyState.stringValue = Self.emptyStateText(routeFilter: routeFilter)

        if let lastError {
            statusLabel.stringValue = TrafficBarLocalization.samplingFailed(lastError)
            statusLabel.textColor = .systemRed
        } else if let lastUpdated {
            statusLabel.stringValue = TrafficBarLocalization.updated(Self.timeFormatter.string(from: lastUpdated))
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = TrafficBarLocalization.buildingSamplingBaseline()
            statusLabel.textColor = .secondaryLabelColor
        }

        if let index = StatisticsPeriod.allCases.firstIndex(of: period) {
            periodControl.selectedSegment = index
        }
        if let index = TrafficRouteFilter.allCases.firstIndex(of: routeFilter) {
            routeControl.selectedSegment = index
        }

        rebuildRows(with: dashboard.items)
    }

    private func headerView() -> NSView {
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        titleStack.alignment = .leading
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(statusLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        rateLabel.alignment = .right
        rateLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleStack, spacer, rateLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("header")
        return stack
    }

    private func totalBand() -> NSView {
        let totalStack = NSStackView()
        totalStack.orientation = .vertical
        totalStack.alignment = .leading
        totalStack.spacing = 1
        totalStack.addArrangedSubview(totalCaptionLabel)
        totalStack.addArrangedSubview(totalValueLabel)

        let routeStack = NSStackView(views: [proxyMetric, directMetric, loopbackMetric])
        routeStack.orientation = .horizontal
        routeStack.alignment = .centerY
        routeStack.distribution = .fillEqually
        routeStack.spacing = 8

        let stack = NSStackView(views: [totalStack, routeStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsetsZero
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("totalBand")

        NSLayoutConstraint.activate([
            routeStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return stack
    }

    private func filterView() -> NSView {
        periodControl.segmentStyle = .rounded
        periodControl.target = self
        periodControl.action = #selector(periodChanged(_:))
        periodControl.translatesAutoresizingMaskIntoConstraints = false
        periodControl.identifier = NSUserInterfaceItemIdentifier("period")

        routeControl.segmentStyle = .rounded
        routeControl.target = self
        routeControl.action = #selector(routeFilterChanged(_:))
        routeControl.translatesAutoresizingMaskIntoConstraints = false
        routeControl.identifier = NSUserInterfaceItemIdentifier("routeFilter")

        let stack = NSStackView(views: [periodControl, routeControl])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = CGFloat(layout.filterSpacing)
        stack.identifier = NSUserInterfaceItemIdentifier("filterWrap")

        NSLayoutConstraint.activate([
            periodControl.widthAnchor.constraint(equalTo: stack.widthAnchor),
            routeControl.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return stack
    }

    private func listView() -> NSView {
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 0
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        emptyState.stringValue = TrafficBarLocalization.emptyState(routeFilter: .all)
        emptyState.alignment = .center
        emptyState.textColor = .secondaryLabelColor

        let clipView = NSClipView()
        clipView.documentView = rowStack
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.identifier = NSUserInterfaceItemIdentifier("list")

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            rowStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -12)
        ])

        return scrollView
    }

    private func footerView() -> NSView {
        let updates = iconButton(symbolName: "arrow.down.circle", tooltip: TrafficBarLocalization.checkForUpdates(), action: #selector(checkForUpdates(_:)))
        let refresh = iconButton(symbolName: "arrow.clockwise", tooltip: TrafficBarLocalization.refreshNow(), action: #selector(refresh(_:)))
        let folder = iconButton(symbolName: "folder", tooltip: TrafficBarLocalization.openDataFolder(), action: #selector(openDataFolder(_:)))
        let quit = iconButton(symbolName: "power", tooltip: TrafficBarLocalization.quit(), action: #selector(quit(_:)))

        let left = Label(style: .caption)
        left.stringValue = "\(TrafficBarLocalization.productName) \(AppVersion.current.tagString)"
        left.textColor = .tertiaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [left, spacer, updates, refresh, folder, quit])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("footer")
        return stack
    }

    private func rebuildRows(with items: [TrafficAppPresentation]) {
        NSLayoutConstraint.deactivate(rowWidthConstraints)
        rowWidthConstraints.removeAll()
        rowStack.removeAllArrangedSubviews()

        if items.isEmpty {
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(emptyState)
            emptyState.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(wrapper)

            let widthConstraint = wrapper.widthAnchor.constraint(equalTo: rowStack.widthAnchor)
            rowWidthConstraints.append(widthConstraint)

            NSLayoutConstraint.activate([
                widthConstraint,
                wrapper.heightAnchor.constraint(equalToConstant: 150),
                emptyState.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
                emptyState.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -18),
                emptyState.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
            ])
            return
        }

        for item in items {
            let row = AppTrafficRowView(item: item, icon: iconProvider.icon(for: item.appName))
            rowStack.addArrangedSubview(row)
            let widthConstraint = row.widthAnchor.constraint(equalTo: rowStack.widthAnchor)
            rowWidthConstraints.append(widthConstraint)
            widthConstraint.isActive = true
        }
    }

    private func iconButton(symbolName: String, tooltip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    @objc private func periodChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard StatisticsPeriod.allCases.indices.contains(index) else {
            return
        }
        onPeriodChange?(StatisticsPeriod.allCases[index])
    }

    @objc private func routeFilterChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard TrafficRouteFilter.allCases.indices.contains(index) else {
            return
        }
        onRouteFilterChange?(TrafficRouteFilter.allCases[index])
    }

    @objc private func refresh(_ sender: NSButton) {
        onRefresh?()
    }

    @objc private func openDataFolder(_ sender: NSButton) {
        onOpenDataFolder?()
    }

    @objc private func checkForUpdates(_ sender: NSButton) {
        onCheckForUpdates?()
    }

    @objc private func quit(_ sender: NSButton) {
        onQuit?()
    }

    private func headerViewWidthConstraint(_ rootStack: NSStackView) -> NSLayoutConstraint {
        guard let header = rootStack.arrangedSubviews.first(where: { $0.identifier?.rawValue == "header" }) else {
            return view.widthAnchor.constraint(equalToConstant: CGFloat(layout.popoverWidth))
        }
        return header.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -CGFloat(layout.contentPadding * 2))
    }

    private func totalBandWidthConstraint(_ rootStack: NSStackView) -> NSLayoutConstraint {
        guard let band = rootStack.arrangedSubviews.first(where: { $0.identifier?.rawValue == "totalBand" }) else {
            return view.widthAnchor.constraint(equalToConstant: CGFloat(layout.popoverWidth))
        }
        return band.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -CGFloat(layout.contentPadding * 2))
    }

    private func filterViewWidthConstraint(_ rootStack: NSStackView) -> NSLayoutConstraint {
        guard let period = rootStack.arrangedSubviews.first(where: { $0.identifier?.rawValue == "filterWrap" }) else {
            return view.widthAnchor.constraint(equalToConstant: CGFloat(layout.popoverWidth))
        }
        return period.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -CGFloat(layout.contentPadding * 2))
    }

    private func footerWidthConstraint(_ rootStack: NSStackView) -> NSLayoutConstraint {
        guard let footer = rootStack.arrangedSubviews.first(where: { $0.identifier?.rawValue == "footer" }) else {
            return view.widthAnchor.constraint(equalToConstant: CGFloat(layout.popoverWidth))
        }
        return footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -CGFloat(layout.contentPadding * 2))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private static func totalCaption(periodTitle: String, routeFilter: TrafficRouteFilter) -> String {
        TrafficBarLocalization.trafficCaption(periodTitle: periodTitle, routeFilter: routeFilter)
    }

    private static func emptyStateText(routeFilter: TrafficRouteFilter) -> String {
        TrafficBarLocalization.emptyState(routeFilter: routeFilter)
    }
}

final class AppTrafficRowView: NSView {
    private let barView: RouteBarView

    init(item: TrafficAppPresentation, icon: NSImage) {
        let layout = TrafficPresentation.dashboardLayout
        self.barView = RouteBarView(routes: item.routes, share: item.share)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = Label(style: .bodyStrong)
        nameLabel.stringValue = item.appName
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let totalLabel = Label(style: .bodyStrong)
        totalLabel.stringValue = item.totalLabel
        totalLabel.alignment = .right
        totalLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detailLabel = Label(style: .caption)
        detailLabel.stringValue = item.detailLabel
        detailLabel.textColor = .secondaryLabelColor

        let liveRateLabel = Label(style: .caption)
        liveRateLabel.stringValue = item.liveRateLabel
        liveRateLabel.textColor = .controlAccentColor

        let topLine = NSStackView(views: [nameLabel, NSView(), totalLabel])
        topLine.orientation = .horizontal
        topLine.alignment = .firstBaseline
        topLine.spacing = 8

        let chipStack = NSStackView()
        chipStack.orientation = .horizontal
        chipStack.alignment = .centerY
        chipStack.spacing = 6
        for route in item.routes {
            chipStack.addArrangedSubview(RouteChipView(route: route))
        }

        let body = NSStackView(views: [topLine, detailLabel, liveRateLabel, barView, chipStack])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 4

        let iconView = AppIconView(image: icon)
        let content = NSStackView(views: [iconView, body])
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 9
        content.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(layout.rowMinimumHeight)),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: separator.topAnchor),
            body.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -CGFloat(layout.appIconSize + 9)),
            topLine.widthAnchor.constraint(equalTo: body.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: body.widthAnchor),
            liveRateLabel.widthAnchor.constraint(equalTo: body.widthAnchor),
            barView.widthAnchor.constraint(equalTo: body.widthAnchor),
            barView.heightAnchor.constraint(equalToConstant: 4),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AppIconView: NSView {
    init(image: NSImage) {
        let size = CGFloat(TrafficPresentation.dashboardLayout.appIconSize)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AppIconProvider {
    private var cache: [String: NSImage] = [:]
    private lazy var applicationURLsByName = buildApplicationIndex()

    func icon(for appName: String) -> NSImage {
        if let cached = cache[appName] {
            return cached
        }

        let resolved = resolveIcon(for: appName) ?? NSWorkspace.shared.icon(for: UTType.applicationBundle)
        resolved.size = NSSize(width: 28, height: 28)
        cache[appName] = resolved
        return resolved
    }

    private func resolveIcon(for appName: String) -> NSImage? {
        let candidates = TrafficPresentation.appIconSearchNames(for: appName)
        guard !candidates.isEmpty else {
            return nil
        }

        // nettop often reports a bundle identifier (for example,
        // com.google.Chrome) instead of the app's display name. Resolve that
        // identifier directly before falling back to name-based matching.
        for candidate in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }

        if let runningIcon = iconFromRunningApplications(matching: candidates) {
            return runningIcon
        }

        for candidate in candidates {
            if let url = applicationURLsByName[candidate.lowercased()] {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }

        return nil
    }

    private func iconFromRunningApplications(matching candidates: [String]) -> NSImage? {
        let loweredCandidates = Set(candidates.map { $0.lowercased() })

        for application in NSWorkspace.shared.runningApplications {
            let names = [
                application.localizedName,
                application.bundleIdentifier,
                application.bundleURL?.deletingPathExtension().lastPathComponent,
                application.executableURL?.deletingPathExtension().lastPathComponent
            ].compactMap { $0?.lowercased() }

            guard names.contains(where: { loweredCandidates.contains($0) }),
                  let bundleURL = application.bundleURL else {
                continue
            }

            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }

    private func buildApplicationIndex() -> [String: URL] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var index: [String: URL] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                indexApp(url, into: &index)
                enumerator.skipDescendants()
            }
        }

        return index
    }

    private func indexApp(_ url: URL, into index: inout [String: URL]) {
        let fileName = url.deletingPathExtension().lastPathComponent
        insert(fileName, url: url, into: &index)

        guard let bundle = Bundle(url: url) else {
            return
        }

        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
        insert(bundle.bundleIdentifier, url: url, into: &index)
        insert(info["CFBundleDisplayName"] as? String, url: url, into: &index)
        insert(info["CFBundleName"] as? String, url: url, into: &index)
    }

    private func insert(_ name: String?, url: URL, into index: inout [String: URL]) {
        guard let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        index[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = url
    }
}

final class MetricPillView: NSView {
    private let valueLabel = Label(style: .bodyStrong)

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    init(title: String, symbolName: String) {
        super.init(frame: .zero)

        let symbol = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage())
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        symbol.contentTintColor = .secondaryLabelColor
        symbol.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = Label(style: .caption)
        titleLabel.stringValue = title
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.stringValue = "0 B"

        let textStack = NSStackView(views: [titleLabel, valueLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let stack = NSStackView(views: [symbol, textStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsetsZero
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 14),
            symbol.heightAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class InlinePillView: NSView {
    init(symbolName: String, label: NSTextField) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 999
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor

        let symbol = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        symbol.contentTintColor = .controlAccentColor

        label.textColor = .controlAccentColor

        let stack = NSStackView(views: [symbol, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 12),
            symbol.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SymbolBadgeView: NSView {
    init(symbolName: String, tintColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = tintColor.withAlphaComponent(0.14).cgColor

        let imageView = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        imageView.contentTintColor = tintColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class RouteChipView: NSView {
    init(route: TrafficRoutePresentation) {
        super.init(frame: .zero)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        dot.layer?.backgroundColor = route.route.displayColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = Label(style: .caption)
        label.stringValue = "\(route.title) \(route.totalLabel)"
        label.textColor = route.route.displayColor

        let stack = NSStackView(views: [dot, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsetsZero
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 5),
            dot.heightAnchor.constraint(equalToConstant: 5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class RouteBarView: NSView {
    private let routes: [TrafficRoutePresentation]
    private let share: Double

    init(routes: [TrafficRoutePresentation], share: Double) {
        self.routes = routes
        self.share = max(0, min(share, 1))
        super.init(frame: .zero)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let background = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.separatorColor.withAlphaComponent(0.34).setFill()
        background.fill()

        let filledWidth = bounds.width * share
        guard filledWidth > 0 else {
            return
        }

        var cursor = CGFloat(0)
        for route in routes {
            let segmentWidth = max(1, filledWidth * route.fraction)
            let segmentRect = NSRect(x: cursor, y: 0, width: min(segmentWidth, filledWidth - cursor), height: bounds.height)
            route.route.displayColor.setFill()
            NSBezierPath(roundedRect: segmentRect, xRadius: radius, yRadius: radius).fill()
            cursor += segmentWidth
            if cursor >= filledWidth {
                break
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class Label: NSTextField {
    enum Style {
        case title
        case headline
        case body
        case bodyStrong
        case caption
    }

    init(style: Style) {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        translatesAutoresizingMaskIntoConstraints = false
        textColor = .labelColor

        switch style {
        case .title:
            font = .systemFont(ofSize: 14, weight: .semibold)
        case .headline:
            font = .monospacedDigitSystemFont(ofSize: 23, weight: .semibold)
        case .body:
            font = .systemFont(ofSize: 12, weight: .regular)
        case .bodyStrong:
            font = .systemFont(ofSize: 12, weight: .semibold)
        case .caption:
            font = .systemFont(ofSize: 10.5, weight: .medium)
            textColor = .secondaryLabelColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class MonitorModel {
    var onChange: (() -> Void)?
    private(set) var summaries: [AppTrafficSummary] = []
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var lastDownloadBytesPerSecond: Double = 0
    private(set) var lastUploadBytesPerSecond: Double = 0

    private let collector: NetworkSnapshotCollecting
    private let proxyProvider: ProxySettingsProviding
    private let queue = DispatchQueue(label: "trafficbar.monitor")
    private let sampleInterval: TimeInterval
    private let store: JSONLinesTrafficStore
    private var timer: Timer?
    private var accumulator = TrafficAccumulator()
    private var lastSampleDate: Date?
    private var lastDeltas: [TrafficDelta] = []
    private var lastSampleElapsed: TimeInterval = 0

    var period: StatisticsPeriod = .day {
        didSet {
            recalculate()
        }
    }

    var routeFilter: TrafficRouteFilter = .all {
        didSet {
            guard oldValue != routeFilter else {
                return
            }
            onChange?()
        }
    }

    var dashboard: TrafficDashboardPresentation {
        TrafficPresentation.dashboard(
            summaries: summaries,
            period: period,
            liveRates: TrafficStatistics.liveRates(
                from: lastDeltas,
                elapsed: lastSampleElapsed,
                routeFilter: routeFilter
            ),
            routeFilter: routeFilter,
            locale: .current
        )
    }

    var storeFileURL: URL {
        store.fileURL
    }

    var statusTitle: String {
        if lastError != nil {
            return "!"
        }

        if lastUpdated == nil {
            return "..."
        }

        return TrafficPresentation.statusBarRateLabel(
            downloadBytesPerSecond: lastDownloadBytesPerSecond,
            uploadBytesPerSecond: lastUploadBytesPerSecond
        )
    }

    init(
        collector: NetworkSnapshotCollecting = NettopCollector(),
        proxyProvider: ProxySettingsProviding = SystemProxySettingsProvider(),
        sampleInterval: TimeInterval = 5,
        storeDirectoryURL: URL = JSONLinesTrafficStore.defaultDirectoryURL()
    ) {
        self.collector = collector
        self.proxyProvider = proxyProvider
        self.sampleInterval = sampleInterval
        self.store = (try? JSONLinesTrafficStore(directoryURL: storeDirectoryURL)) ?? (try! JSONLinesTrafficStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("TrafficBar", isDirectory: true), legacyFileURL: nil))
        self.summaries = TrafficStatistics.aggregate(store.deltas, period: .day)
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        let period = self.period
        queue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                let proxySettings = self.proxyProvider.currentSettings()
                let snapshot = try self.collector.collect()
                let deltas = self.accumulator.ingest(snapshot, proxySettings: proxySettings)
                try self.store.append(deltas)

                let downloadBytes = deltas.reduce(UInt64(0)) { $0 + $1.bytesIn }
                let uploadBytes = deltas.reduce(UInt64(0)) { $0 + $1.bytesOut }
                let elapsed = self.lastSampleDate.map { snapshot.timestamp.timeIntervalSince($0) } ?? self.sampleInterval
                let downloadRate = elapsed > 0 ? Double(downloadBytes) / elapsed : 0
                let uploadRate = elapsed > 0 ? Double(uploadBytes) / elapsed : 0
                self.lastSampleDate = snapshot.timestamp

                let summaries = TrafficStatistics.aggregate(self.store.deltas, period: period, now: Date())

                DispatchQueue.main.async {
                    self.lastError = nil
                    self.lastUpdated = snapshot.timestamp
                    self.lastDownloadBytesPerSecond = downloadRate
                    self.lastUploadBytesPerSecond = uploadRate
                    self.lastDeltas = deltas
                    self.lastSampleElapsed = elapsed
                    self.summaries = summaries
                    self.onChange?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = Self.shortError(error)
                    self.onChange?()
                }
            }
        }
    }

    private func recalculate() {
        let period = self.period
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let summaries = TrafficStatistics.aggregate(self.store.deltas, period: period, now: Date())
            DispatchQueue.main.async {
                self.summaries = summaries
                self.onChange?()
            }
        }
    }

    private static func shortError(_ error: Error) -> String {
        if error as? CommandRunnerError == .timedOut {
            return TrafficBarLocalization.nettopTimedOut()
        }

        let text = String(describing: error)
        if text.count <= 80 {
            return text
        }
        return String(text.prefix(77)) + "..."
    }
}

private extension NSStackView {
    func removeAllArrangedSubviews() {
        for subview in arrangedSubviews {
            removeArrangedSubview(subview)
            subview.deactivateConstraintsRecursively()
            subview.removeFromSuperview()
        }
    }
}

private extension NSView {
    func deactivateConstraintsRecursively() {
        NSLayoutConstraint.deactivate(constraints)
        subviews.forEach { $0.deactivateConstraintsRecursively() }
    }
}

private extension TrafficRoute {
    var displayColor: NSColor {
        switch self {
        case .proxy:
            return NSColor.systemGreen
        case .direct:
            return NSColor.controlAccentColor
        case .loopback:
            return NSColor.systemOrange
        case .unknown:
            return NSColor.secondaryLabelColor
        }
    }
}
