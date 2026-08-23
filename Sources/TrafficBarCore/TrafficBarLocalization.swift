import Foundation

public enum TrafficBarLocalization {
    public static let productName = "流量管家"

    public enum Language: Sendable {
        case english
        case simplifiedChinese
    }

    public static func language(for locale: Locale = .current) -> Language {
        if locale.language.languageCode?.identifier.lowercased() == "zh" {
            return .simplifiedChinese
        }

        // A bundled app can inherit its development region instead of the
        // user's preferred language. Read the macOS preference as a fallback,
        // but only when the caller is asking for the current locale. Explicit
        // locales remain deterministic for tests and other callers.
        guard locale.identifier == Locale.current.identifier else {
            return .english
        }

        let preferredLanguage = UserDefaults.standard
            .stringArray(forKey: "AppleLanguages")?
            .first?
            .lowercased()
        let preferredLocale = UserDefaults.standard
            .string(forKey: "AppleLocale")?
            .lowercased()

        if preferredLanguage?.hasPrefix("zh") == true
            || preferredLocale?.hasPrefix("zh") == true {
            return .simplifiedChinese
        }

        return .english
    }

    public static func routeTitle(_ route: TrafficRoute, locale: Locale = .current) -> String {
        switch (route, language(for: locale)) {
        case (.proxy, .simplifiedChinese): return "代理"
        case (.direct, .simplifiedChinese): return "直连"
        case (.loopback, .simplifiedChinese): return "本地"
        case (.unknown, .simplifiedChinese): return "未知"
        case (.proxy, .english): return "Proxy"
        case (.direct, .english): return "Direct"
        case (.loopback, .english): return "Local"
        case (.unknown, .english): return "Unknown"
        }
    }

    public static func routeFilterTitle(_ filter: TrafficRouteFilter, locale: Locale = .current) -> String {
        guard let route = filter.route else {
            return language(for: locale) == .simplifiedChinese ? "全部" : "All"
        }
        return routeTitle(route, locale: locale)
    }

    public static func periodTitle(_ period: StatisticsPeriod, locale: Locale = .current) -> String {
        switch (period, language(for: locale)) {
        case (.hour, .simplifiedChinese): return "小时"
        case (.day, .simplifiedChinese): return "今天"
        case (.week, .simplifiedChinese): return "本周"
        case (.month, .simplifiedChinese): return "本月"
        case (.hour, .english): return "Hour"
        case (.day, .english): return "Today"
        case (.week, .english): return "Week"
        case (.month, .english): return "Month"
        }
    }

    public static func trafficCaption(
        periodTitle: String,
        routeFilter: TrafficRouteFilter,
        locale: Locale = .current
    ) -> String {
        switch language(for: locale) {
        case .simplifiedChinese:
            if let route = routeFilter.route {
                return "\(periodTitle)\(routeTitle(route, locale: locale))流量"
            }
            return "\(periodTitle)流量"
        case .english:
            guard let route = routeFilter.route else {
                return "\(periodTitle) traffic"
            }
            return "\(periodTitle) \(routeTitle(route, locale: locale).lowercased()) traffic"
        }
    }

    public static func detailLabel(
        download: String,
        upload: String,
        locale: Locale = .current
    ) -> String {
        switch language(for: locale) {
        case .simplifiedChinese:
            return "下载 \(download)  上传 \(upload)"
        case .english:
            return "Down \(download)  Up \(upload)"
        }
    }

    public static func liveRateLabel(_ rate: String, locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "当前 \(rate)" : "Now \(rate)"
    }

    public static func samplingFailed(_ error: String, locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "采样失败：\(error)" : "Sampling failed: \(error)"
    }

    public static func updated(_ time: String, locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "更新于 \(time)" : "Updated \(time)"
    }

    public static func buildingSamplingBaseline(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "正在建立采样基线" : "Building sampling baseline"
    }

    public static func emptyState(routeFilter: TrafficRouteFilter, locale: Locale = .current) -> String {
        switch language(for: locale) {
        case .simplifiedChinese:
            guard let route = routeFilter.route else {
                return "暂无流量变化，请保持\(productName)运行几秒。"
            }
            return "此时间段暂无\(routeTitle(route, locale: locale))流量。"
        case .english:
            guard let route = routeFilter.route else {
                return "No traffic deltas yet. Keep TrafficBar running for a few seconds."
            }
            return "No \(routeTitle(route, locale: locale).lowercased()) traffic in this period."
        }
    }

    public static func checkForUpdates(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "检查更新" : "Check for Updates"
    }

    public static func refreshNow(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "立即刷新" : "Refresh now"
    }

    public static func openDataFolder(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "打开数据文件夹" : "Open data folder"
    }

    public static func quit(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "退出" : "Quit"
    }

    public static func nettopTimedOut(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese ? "nettop 采样超时" : "nettop timed out"
    }

    public static func invalidUpdateRepository(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese
            ? "无法创建更新仓库地址。"
            : "The update repository URL could not be created."
    }

    public static func invalidUpdateResponse(locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese
            ? "GitHub 返回了无效的更新响应。"
            : "GitHub returned an invalid update response."
    }

    public static func updateRequestFailed(_ statusCode: Int, locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese
            ? "检查 GitHub 更新失败，HTTP \(statusCode)。"
            : "GitHub update check failed with HTTP \(statusCode)."
    }

    public static func invalidReleaseTag(_ tag: String, locale: Locale = .current) -> String {
        language(for: locale) == .simplifiedChinese
            ? "最新 GitHub 版本标签无效：\(tag)。"
            : "The latest GitHub release tag is not a valid version: \(tag)."
    }
}
