import XCTest
@testable import TrafficBarCore

final class AppUpdateTests: XCTestCase {
    func testCurrentVersionUsesRepositoryVersionFallback() throws {
        let versionText = try String(contentsOf: URL(fileURLWithPath: "VERSION"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = AppVersion.current

        XCTAssertEqual(version.displayString, versionText)
        XCTAssertEqual(version.tagString, "v\(versionText)")
    }

    func testCurrentVersionResolverPrefersBundleInfo() throws {
        let version = try XCTUnwrap(AppVersionResolver.resolve(
            bundleVersion: "1.2.3",
            versionFileText: "0.1.9"
        ))

        XCTAssertEqual(version.displayString, "1.2.3")
    }

    func testCurrentVersionResolverFallsBackToVersionFile() throws {
        let version = try XCTUnwrap(AppVersionResolver.resolve(
            bundleVersion: nil,
            versionFileText: "0.1.9\n"
        ))

        XCTAssertEqual(version.displayString, "0.1.9")
    }

    func testComparesSemanticVersionsFromTags() throws {
        let older = try XCTUnwrap(AppVersion("v0.1.9"))
        let newer = try XCTUnwrap(AppVersion("v0.2.0"))
        let release = try XCTUnwrap(AppVersion("v1.0.0"))
        let prerelease = try XCTUnwrap(AppVersion("v1.0.0-beta.1"))

        XCTAssertLessThan(older, newer)
        XCTAssertLessThan(prerelease, release)
    }

    func testDecodesGitHubReleaseAndDetectsUpdate() throws {
        let data = Data("""
        {
          "tag_name": "v0.2.0",
          "html_url": "https://example.com/TrafficBar/releases/tag/v0.2.0"
        }
        """.utf8)

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let status = AppUpdateEvaluator.evaluate(release: release, currentVersion: try XCTUnwrap(AppVersion("0.1.0")))

        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(status, .updateAvailable(
            currentVersion: try XCTUnwrap(AppVersion("0.1.0")),
            latestVersion: try XCTUnwrap(AppVersion("v0.2.0")),
            releaseURL: try XCTUnwrap(URL(string: "https://example.com/TrafficBar/releases/tag/v0.2.0"))
        ))
    }

    func testDetectsUpToDateRelease() throws {
        let release = GitHubRelease(
            tagName: "v0.1.0",
            releaseURL: try XCTUnwrap(URL(string: "https://example.com/TrafficBar/releases/tag/v0.1.0"))
        )

        let status = AppUpdateEvaluator.evaluate(release: release, currentVersion: try XCTUnwrap(AppVersion("0.1.0")))

        XCTAssertEqual(status, .upToDate(currentVersion: try XCTUnwrap(AppVersion("0.1.0"))))
    }

    func testCheckerTreatsMissingLatestReleaseAsNoPublishedRelease() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let checker = GitHubUpdateChecker(
            owner: "example",
            repository: "TrafficBar",
            currentVersion: try XCTUnwrap(AppVersion("0.1.0")),
            session: URLSession(configuration: configuration)
        )

        let status = try await checker.check()

        XCTAssertEqual(status, .noPublishedRelease(currentVersion: try XCTUnwrap(AppVersion("0.1.0"))))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            XCTFail("Missing request handler")
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
