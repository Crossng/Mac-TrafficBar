import Foundation

public struct AppVersion: Hashable, Comparable, Sendable {
    public static var current: AppVersion {
        AppVersionResolver.current()
    }

    public let rawValue: String

    private let numericComponents: [Int]
    private let prerelease: String?

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let withoutPrefix = trimmed.dropFirst(trimmed.lowercased().hasPrefix("v") ? 1 : 0)
        let withoutBuildMetadata = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let versionParts = withoutBuildMetadata.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericText = versionParts[0]
        let prereleaseText = versionParts.count > 1 ? String(versionParts[1]) : nil
        let components = numericText.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }

        guard components.count >= 2,
              components.count <= 3,
              components.count == numericText.split(separator: ".", omittingEmptySubsequences: false).count else {
            return nil
        }

        self.rawValue = String(withoutBuildMetadata)
        self.numericComponents = components
        self.prerelease = prereleaseText?.isEmpty == false ? prereleaseText : nil
    }

    public var displayString: String {
        var value = paddedNumericComponents.map(String.init).joined(separator: ".")
        if let prerelease {
            value += "-\(prerelease)"
        }
        return value
    }

    public var tagString: String {
        "v\(displayString)"
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.paddedNumericComponents == rhs.paddedNumericComponents && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in zip(lhs.paddedNumericComponents, rhs.paddedNumericComponents) where left != right {
            return left < right
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (left?, right?):
            return comparePrerelease(left, right) == .orderedAscending
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paddedNumericComponents)
        hasher.combine(prerelease)
    }

    private var paddedNumericComponents: [Int] {
        numericComponents + Array(repeating: 0, count: max(0, 3 - numericComponents.count))
    }

    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let rightParts = rhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        for index in 0..<max(leftParts.count, rightParts.count) {
            guard leftParts.indices.contains(index) else {
                return .orderedAscending
            }
            guard rightParts.indices.contains(index) else {
                return .orderedDescending
            }

            let left = leftParts[index]
            let right = rightParts[index]
            if let leftNumber = Int(left), let rightNumber = Int(right), leftNumber != rightNumber {
                return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
            }
            if Int(left) != nil, Int(right) == nil {
                return .orderedAscending
            }
            if Int(left) == nil, Int(right) != nil {
                return .orderedDescending
            }
            if left != right {
                return left < right ? .orderedAscending : .orderedDescending
            }
        }

        return .orderedSame
    }
}

enum AppVersionResolver {
    static func current(bundle: Bundle = .main, fileManager: FileManager = .default) -> AppVersion {
        guard let version = resolve(
            bundleVersion: bundleInfoVersion(bundle),
            versionFileText: versionFileText(fileManager: fileManager)
        ) else {
            fatalError("Missing valid TrafficBar version. Set CFBundleShortVersionString or VERSION.")
        }

        return version
    }

    static func resolve(bundleVersion: String?, versionFileText: String?) -> AppVersion? {
        [bundleVersion, versionFileText]
            .compactMap { $0 }
            .lazy
            .compactMap(AppVersion.init)
            .first
    }

    private static func bundleInfoVersion(_ bundle: Bundle) -> String? {
        guard bundle.bundleIdentifier == "com.crossng.TrafficBar" else {
            return nil
        }

        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func versionFileText(fileManager: FileManager) -> String? {
        guard let url = versionFileURL(fileManager: fileManager) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func versionFileURL(fileManager: FileManager) -> URL? {
        var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0..<10 {
            let candidate = directory.appendingPathComponent("VERSION", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        return nil
    }
}

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let releaseURL: URL

    public init(tagName: String, releaseURL: URL) {
        self.tagName = tagName
        self.releaseURL = releaseURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case releaseURL = "html_url"
    }
}

public enum AppUpdateStatus: Equatable, Sendable {
    case updateAvailable(currentVersion: AppVersion, latestVersion: AppVersion, releaseURL: URL)
    case upToDate(currentVersion: AppVersion)
    case noPublishedRelease(currentVersion: AppVersion)
}

public enum AppUpdateEvaluator {
    public static func evaluate(release: GitHubRelease, currentVersion: AppVersion = .current) -> AppUpdateStatus {
        guard let latestVersion = AppVersion(release.tagName),
              latestVersion > currentVersion else {
            return .upToDate(currentVersion: currentVersion)
        }

        return .updateAvailable(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: release.releaseURL
        )
    }
}

public enum AppUpdateError: LocalizedError, Equatable {
    case invalidRepository
    case invalidResponse
    case requestFailed(Int)
    case invalidReleaseTag(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return TrafficBarLocalization.invalidUpdateRepository()
        case .invalidResponse:
            return TrafficBarLocalization.invalidUpdateResponse()
        case let .requestFailed(statusCode):
            return TrafficBarLocalization.updateRequestFailed(statusCode)
        case let .invalidReleaseTag(tag):
            return TrafficBarLocalization.invalidReleaseTag(tag)
        }
    }
}

public struct GitHubUpdateChecker {
    public let owner: String
    public let repository: String
    public let currentVersion: AppVersion

    private let session: URLSession

    public init(
        owner: String,
        repository: String,
        currentVersion: AppVersion = .current,
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repository = repository
        self.currentVersion = currentVersion
        self.session = session
    }

    public func check() async throws -> AppUpdateStatus {
        let release: GitHubRelease
        do {
            release = try await latestRelease()
        } catch AppUpdateError.requestFailed(404) {
            return .noPublishedRelease(currentVersion: currentVersion)
        }

        guard AppVersion(release.tagName) != nil else {
            throw AppUpdateError.invalidReleaseTag(release.tagName)
        }
        return AppUpdateEvaluator.evaluate(release: release, currentVersion: currentVersion)
    }

    public func latestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw AppUpdateError.invalidRepository
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TrafficBar/\(currentVersion.displayString)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.requestFailed(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
