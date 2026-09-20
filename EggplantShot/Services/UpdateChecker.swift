import Foundation

/// Checks GitHub Releases for a newer tagged version than the running build.
enum UpdateChecker {
    struct Release {
        let version: String
        let htmlURL: URL
    }

    enum CheckResult {
        case upToDate
        case updateAvailable(Release)
    }

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/uniquejava/EggplantShot/releases/latest"
    )!

    /// Built per check so a proxy edit in Preferences → Network applies without a relaunch.
    private static func makeSession() -> URLSession {
        guard let proxy = NetworkPrefs.proxyDictionary else { return .shared }
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = proxy
        return URLSession(configuration: config)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    static func checkForUpdates() async throws -> CheckResult {
        let (data, response) = try await makeSession().data(from: latestReleaseURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

        if isNewer(latestVersion, than: currentVersion) {
            return .updateAvailable(Release(version: latestVersion, htmlURL: release.htmlURL))
        }
        return .upToDate
    }

    /// Compares dot-separated numeric version strings, e.g. "0.10.0" > "0.4.0".
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhsParts.count, rhsParts.count) {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
