import Foundation
@testable import HyperMugCore

func updatesTests() {
    versionComparison()
    versionLookup()
    outcomes()
    requestHeaders()
}

private func versionComparison() {
    expect(isRemoteNewer("0.2", than: "0.1"))
    expect(!isRemoteNewer("0.1", than: "0.2"))
    expect(!isRemoteNewer("0.1", than: "0.1"), "equal is not newer")
    expect(isRemoteNewer("v1.0", than: "0.9"), "v prefix")
    expect(isRemoteNewer("V1.0", than: "0.9"), "capital V prefix")
    expect(isRemoteNewer("1.0.1", than: "1.0"), "extra component on the remote")
    expect(!isRemoteNewer("1.0", than: "1.0.1"), "extra component on the local")
    expect(!isRemoteNewer("1.0.0", than: "1.0"), "trailing zeros are equal")
    expect(isRemoteNewer("1.10", than: "1.9"), "compared numerically, not as text")
    expect(isRemoteNewer("  v2 \n", than: "1.9"), "surrounding whitespace")
    expect(!isRemoteNewer("abc", than: "0.1"), "non-numeric parts count as 0")
    expect(!isRemoteNewer("1.x", than: "1.0"))
    expect(isRemoteNewer("1.1", than: "1.x"))
}

private func versionLookup() {
    expectEqual(appVersion(infoDictionary: ["CFBundleShortVersionString": "2.5"]), "2.5")
    expectEqual(appVersion(infoDictionary: nil), "0.1")
    expectEqual(appVersion(infoDictionary: ["CFBundleVersion": "9"]), "0.1", "key missing")
    expectEqual(appVersion(infoDictionary: ["CFBundleShortVersionString": 3]), "0.1", "wrong type")
}

private func outcomes() {
    func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    let releases = githubReleasesURL
    let goodBody = json(["tag_name": "v0.3", "html_url": "https://github.com/maxmeis/HyperMug/releases/tag/v0.3"])

    // The update check reads the renamed repository (R9).
    expectEqual(githubLatestAPI.absoluteString, "https://api.github.com/repos/maxmeis/HyperMug/releases/latest")
    expectEqual(releases.absoluteString, "https://github.com/maxmeis/HyperMug/releases")

    // Transport error beats everything.
    expectEqual(updateOutcome(errorDescription: "offline", status: 200, body: goodBody, local: "0.2"),
                UpdateAlert(title: "Update check failed", text: "offline", openURL: releases))

    // No releases yet.
    expectEqual(updateOutcome(errorDescription: nil, status: 404, body: nil, local: "0.2"),
                UpdateAlert(title: "HyperMug 0.2", text: "No GitHub releases yet — you're on the latest build.", openURL: nil))

    // Unexpected responses.
    let unexpected: [(Int, Data?, String)] = [
        (500, goodBody, "HTTP 500 with a valid body"),
        (0, nil, "no HTTP response"),
        (200, nil, "no body"),
        (200, Data("not json".utf8), "body is not JSON"),
        (200, json([1, 2]), "JSON is not an object"),
        (200, json(["name": "x"]), "tag_name missing"),
        (200, json(["tag_name": 3]), "tag_name is not a string"),
    ]
    for (status, body, why) in unexpected {
        let alert = updateOutcome(errorDescription: nil, status: status, body: body, local: "0.2")
        expectEqual(alert.title, "Update check failed", why)
        expectEqual(alert.text, "Unexpected response from GitHub (HTTP \(status)).", why)
        expectEqual(alert.openURL, releases, why)
    }

    // Newer release: link to its page, or to the releases list when html_url is unusable.
    expectEqual(updateOutcome(errorDescription: nil, status: 200, body: goodBody, local: "0.2"),
                UpdateAlert(title: "Update available", text: "HyperMug v0.3 is on GitHub (you have 0.2).",
                            openURL: URL(string: "https://github.com/maxmeis/HyperMug/releases/tag/v0.3")))
    for html in [nil, "", 7] as [Any?] {
        var object: [String: Any] = ["tag_name": "v0.3"]
        if let html { object["html_url"] = html }
        let alert = updateOutcome(errorDescription: nil, status: 200, body: json(object), local: "0.2")
        expectEqual(alert.title, "Update available", "html_url \(String(describing: html))")
        expectEqual(alert.openURL, releases, "html_url \(String(describing: html))")
    }

    // Up to date: same or older remote; no button.
    for tag in ["v0.2", "0.2", "0.1"] {
        expectEqual(updateOutcome(errorDescription: nil, status: 200, body: json(["tag_name": tag]), local: "0.2"),
                    UpdateAlert(title: "HyperMug 0.2", text: "You're up to date with GitHub (\(tag)).", openURL: nil), tag)
    }
}

private func requestHeaders() {
    expectEqual(updateRequestHeaders(version: "0.2"),
                ["Accept": "application/vnd.github+json", "User-Agent": "HyperMug/0.2"])
}
