import XCTest
@testable import TrafficBarCore

final class TrafficPresentationTests: XCTestCase {
    func testBuildsDashboardPresentationWithTotalsAndRoutes() {
        let summaries = [
            AppTrafficSummary(
                appName: "Safari",
                routeTotals: [
                    .proxy: TrafficCounter(bytesIn: 1_024, bytesOut: 1_024),
                    .direct: TrafficCounter(bytesIn: 2_048, bytesOut: 0)
                ]
            ),
            AppTrafficSummary(
                appName: "Code",
                routeTotals: [
                    .direct: TrafficCounter(bytesIn: 512, bytesOut: 512)
                ]
            )
        ]

        let dashboard = TrafficPresentation.dashboard(
            summaries: summaries,
            period: .day,
            limit: 8
        )

        XCTAssertEqual(dashboard.periodTitle, "Today")
        XCTAssertEqual(dashboard.totalLabel, "5.0 KB")
        XCTAssertEqual(dashboard.proxyLabel, "2.0 KB")
        XCTAssertEqual(dashboard.directLabel, "3.0 KB")
        XCTAssertEqual(dashboard.items.map(\.appName), ["Safari", "Code"])
        XCTAssertEqual(dashboard.items[0].totalLabel, "4.0 KB")
        XCTAssertEqual(dashboard.items[0].detailLabel, "Down 3.0 KB  Up 1.0 KB")
        XCTAssertEqual(dashboard.items[0].share, 1.0)
        XCTAssertEqual(dashboard.items[1].share, 0.25)
        XCTAssertEqual(dashboard.items[0].routes.map(\.title), ["Proxy", "Direct"])
        XCTAssertEqual(dashboard.items[0].routes.map(\.detailLabel), ["Down 1.0 KB  Up 1.0 KB", "Down 2.0 KB  Up 0 B"])
    }

    func testBuildsDashboardPresentationWithPerAppLiveRates() {
        let summaries = [
            AppTrafficSummary(
                appName: "Safari",
                routeTotals: [
                    .direct: TrafficCounter(bytesIn: 3_072, bytesOut: 1_024)
                ]
            ),
            AppTrafficSummary(
                appName: "Code",
                routeTotals: [
                    .direct: TrafficCounter(bytesIn: 1_024, bytesOut: 512)
                ]
            )
        ]

        let dashboard = TrafficPresentation.dashboard(
            summaries: summaries,
            period: .day,
            limit: 8,
            liveRates: [
                "Safari": TrafficRate(downloadBytesPerSecond: 2_048, uploadBytesPerSecond: 512)
            ]
        )

        XCTAssertEqual(dashboard.items[0].liveRateLabel, "Now ↓ 2.0 KB/s  ↑ 512 B/s")
        XCTAssertEqual(dashboard.items[1].liveRateLabel, "Now ↓ 0 B/s  ↑ 0 B/s")
    }

    func testFiltersDashboardPresentationByRoute() {
        let summaries = [
            AppTrafficSummary(
                appName: "Safari",
                routeTotals: [
                    .proxy: TrafficCounter(bytesIn: 1_024, bytesOut: 1_024),
                    .direct: TrafficCounter(bytesIn: 8_192, bytesOut: 0)
                ]
            ),
            AppTrafficSummary(
                appName: "Code",
                routeTotals: [
                    .direct: TrafficCounter(bytesIn: 4_096, bytesOut: 0)
                ]
            ),
            AppTrafficSummary(
                appName: "Terminal",
                routeTotals: [
                    .loopback: TrafficCounter(bytesIn: 512, bytesOut: 512)
                ]
            )
        ]

        let dashboard = TrafficPresentation.dashboard(
            summaries: summaries,
            period: .day,
            limit: 8,
            routeFilter: .proxy
        )

        XCTAssertEqual(dashboard.totalLabel, "2.0 KB")
        XCTAssertEqual(dashboard.proxyLabel, "2.0 KB")
        XCTAssertEqual(dashboard.directLabel, "12.0 KB")
        XCTAssertEqual(dashboard.loopbackLabel, "1.0 KB")
        XCTAssertEqual(dashboard.items.map(\.appName), ["Safari"])
        XCTAssertEqual(dashboard.items[0].totalLabel, "2.0 KB")
        XCTAssertEqual(dashboard.items[0].detailLabel, "Down 1.0 KB  Up 1.0 KB")
        XCTAssertEqual(dashboard.items[0].routes.map(\.title), ["Proxy"])
    }

    func testBuildsCompactRateLabelWithDownloadAndUpload() {
        let label = TrafficPresentation.rateLabel(downloadBytesPerSecond: 85_920, uploadBytesPerSecond: 12_288)

        XCTAssertEqual(label, "↓ 83.9 KB/s  ↑ 12.0 KB/s")
    }

    func testBuildsStackedRateLabelWithDownloadAndUpload() {
        let label = TrafficPresentation.stackedRateLabel(downloadBytesPerSecond: 15_413_248, uploadBytesPerSecond: 674)

        XCTAssertEqual(label, "↓ 14.7 MB/s\n↑ 674 B/s")
    }

    func testBuildsNarrowStatusBarRateLabel() {
        let label = TrafficPresentation.statusBarRateLabel(downloadBytesPerSecond: 15_413_248, uploadBytesPerSecond: 674)

        XCTAssertEqual(label, "↓14.7M/s\n↑674B/s")
    }

    func testBuildsInlineStatusBarRateLabelForNativeButtonTitle() {
        let label = TrafficPresentation.inlineStatusBarRateLabel(downloadBytesPerSecond: 15_413_248, uploadBytesPerSecond: 674)

        XCTAssertEqual(label, "↓14.7M/s  ↑674B/s")
    }

    func testStatusBarRateLayoutCentersIconAgainstTwoLineTextBlock() {
        let layout = TrafficPresentation.statusBarRateLayout

        XCTAssertEqual(layout.iconSize, 14)
        XCTAssertEqual(layout.lineHeight, 10)
        XCTAssertEqual(layout.textBlockHeight, 20)
        XCTAssertEqual(layout.contentHeight, 20)
        XCTAssertEqual(layout.minimumItemHeight, 22)
        XCTAssertEqual(layout.textColumnWidth, 52)
        XCTAssertEqual(layout.statusItemWidth, 82)
    }

    func testDashboardLayoutKeepsMenuCompact() {
        let layout = TrafficPresentation.dashboardLayout

        XCTAssertEqual(layout.popoverWidth, 360)
        XCTAssertEqual(layout.popoverHeight, 500)
        XCTAssertEqual(layout.contentPadding, 14)
        XCTAssertEqual(layout.sectionSpacing, 10)
        XCTAssertEqual(layout.filterControlRows, 2)
        XCTAssertEqual(layout.appIconSize, 28)
        XCTAssertEqual(layout.rowMinimumHeight, 88)
    }

    func testBuildsAppIconSearchNamesForHelperProcesses() {
        XCTAssertEqual(
            TrafficPresentation.appIconSearchNames(for: "Code Helper (Plugin)"),
            ["Code Helper (Plugin)", "Code Helper", "Code"]
        )
        XCTAssertEqual(
            TrafficPresentation.appIconSearchNames(for: "Google Chrome Helper"),
            ["Google Chrome Helper", "Google Chrome"]
        )
        XCTAssertEqual(
            TrafficPresentation.appIconSearchNames(for: "Safari"),
            ["Safari"]
        )
    }
}
