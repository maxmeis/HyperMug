import Foundation

/// The GitHub repository the update check reads releases from.
public let githubRepo = "maxmeis/HyperMug"
public let githubReleasesURL = URL(string: "https://github.com/\(githubRepo)/releases")!
public let githubLatestAPI = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
public let updateRequestTimeout: TimeInterval = 15

/// The app's version from its Info.plist dictionary; "0.1" when absent.
public func appVersion(infoDictionary: [String: Any]?) -> String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
}

/// Compare dotted versions like "0.1" / "v1.2.3". Returns true if `remote` is newer than `local`.
public func isRemoteNewer(_ remote: String, than local: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
    let a = parts(local)
    let b = parts(remote)
    let n = max(a.count, b.count)
    for i in 0..<n {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if y != x { return y > x }
    }
    return false
}

/// What to tell the user after an update check. `openURL` non-nil: offer an "Open GitHub" button.
public struct UpdateAlert: Equatable {
    public let title: String
    public let text: String
    public let openURL: URL?

    public init(title: String, text: String, openURL: URL?) {
        self.title = title
        self.text = text
        self.openURL = openURL
    }
}

/// Decides the alert from the outcome of the request to `githubLatestAPI`.
/// `errorDescription`: the transport error, if any. `status`: HTTP status, 0 when there was no HTTP response.
public func updateOutcome(errorDescription: String?, status: Int, body: Data?, local: String) -> UpdateAlert {
    if let errorDescription {
        return UpdateAlert(title: "Update check failed", text: errorDescription, openURL: githubReleasesURL)
    }
    // No releases published yet
    if status == 404 {
        return UpdateAlert(
            title: "HyperMug \(local)",
            text: "No GitHub releases yet — you're on the latest build.",
            openURL: nil
        )
    }
    guard status == 200, let body,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let tag = json["tag_name"] as? String else {
        return UpdateAlert(
            title: "Update check failed",
            text: "Unexpected response from GitHub (HTTP \(status)).",
            openURL: githubReleasesURL
        )
    }
    let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? githubReleasesURL
    if isRemoteNewer(tag, than: local) {
        return UpdateAlert(
            title: "Update available",
            text: "HyperMug \(tag) is on GitHub (you have \(local)).",
            openURL: htmlURL
        )
    }
    return UpdateAlert(
        title: "HyperMug \(local)",
        text: "You're up to date with GitHub (\(tag)).",
        openURL: nil
    )
}

/// Headers for the GitHub API request.
public func updateRequestHeaders(version: String) -> [String: String] {
    [
        "Accept": "application/vnd.github+json",
        "User-Agent": "HyperMug/\(version)",
    ]
}
