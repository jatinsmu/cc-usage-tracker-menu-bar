import Foundation

// MARK: - Release info

/// A published release as the updater cares about it.
struct ReleaseInfo: Equatable {
    let version: String        // normalized, no leading "v"
    let pageURL: URL           // human-facing release page (fallback)
    let assetURL: URL?         // direct .zip download, if the release has one
    let assetName: String?
}

// MARK: - Errors

enum UpdateError: Error, LocalizedError {
    case noAsset
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .noAsset:           return "This release has no downloadable build yet."
        case .badResponse(let c): return "Couldn't reach GitHub (HTTP \(c))."
        }
    }
}

// MARK: - Update checker

/// Checks GitHub Releases for a newer build and downloads the asset.
///
/// This is the *second* network endpoint in the app (alongside api.anthropic.com).
/// Like the usage API it must degrade gracefully — a missing release, offline
/// network, or shape change should never crash; callers treat any failure as
/// "no update known".
enum UpdateChecker {
    // owner/repo — keep in sync with the release workflow.
    private static let releasesLatest = URL(
        string: "https://api.github.com/repos/jatinsmu/cc-usage-tracker-menu-bar/releases/latest")!

    /// The running app's marketing version (CFBundleShortVersionString).
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    // MARK: Pure logic (unit-tested)

    /// True when `latest` is a strictly higher semantic version than `current`.
    /// Tolerant of a leading "v" and of differing component counts
    /// ("1.1" > "1.0.9"; missing components count as 0).
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = components(latest)
        let c = components(current)
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Parse GitHub's `releases/latest` payload into a `ReleaseInfo`.
    /// Returns nil for anything unexpected (no tag, garbage) so callers can
    /// treat it as "no update known". Picks the first `.zip` asset.
    static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = obj["tag_name"] as? String,
            let page = (obj["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }

        let assets = (obj["assets"] as? [[String: Any]]) ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let assetURL = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let assetName = zip?["name"] as? String

        return ReleaseInfo(version: normalize(tag), pageURL: page,
                           assetURL: assetURL, assetName: assetName)
    }

    private static func normalize(_ v: String) -> String {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    private static func components(_ v: String) -> [Int] {
        normalize(v).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    // MARK: Network

    /// Fetch the latest release. Returns nil when there are no releases yet (404)
    /// or the payload can't be understood.
    static func checkLatest() async throws -> ReleaseInfo? {
        var req = URLRequest(url: releasesLatest, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CCUsageBar", forHTTPHeaderField: "User-Agent") // GitHub requires a UA

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }            // repo has no releases yet
        guard http.statusCode == 200 else { throw UpdateError.badResponse(http.statusCode) }
        return parseLatest(data)
    }

    /// Download a release asset into ~/Downloads and return the saved file URL.
    static func download(_ asset: URL) async throws -> URL {
        let (tmp, response) = try await URLSession.shared.download(from: asset)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse(http.statusCode)
        }
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dest = uniqueDestination(in: downloads,
                                     name: asset.lastPathComponent.isEmpty ? "CCUsageBar.zip"
                                                                           : asset.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Avoid clobbering an existing download: append " (1)", " (2)", …
    private static func uniqueDestination(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 1
        repeat {
            let suffixed = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(suffixed)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
