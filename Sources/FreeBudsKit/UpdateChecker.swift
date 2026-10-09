import Foundation
import AppKit

/// Looks for a newer release on GitHub and downloads it. It only talks to the network when asked: there is no
/// check in the background.
@MainActor
public final class UpdateChecker: ObservableObject {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(version: String)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }

    private static let endpoint = URL(string: "https://api.github.com/repos/edufigueiredos/free-buds-manager/releases/latest")!
    private var latestAsset: Asset?

    public init() {}

    public var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    public func check() async {
        state = .checking
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = Self.stripV(release.tag_name)
            guard Self.isNewer(version, than: currentVersion) else {
                state = .upToDate
                DiagnosticLog.write("update", "up to date: this is \(currentVersion), the latest is \(version)")
                return
            }
            latestAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
            state = latestAsset == nil ? .failed("The release has no installer.") : .available(version: version)
            DiagnosticLog.write("update", "new version \(version) available (this is \(currentVersion))")
        } catch {
            state = .failed(error.localizedDescription)
            DiagnosticLog.write("update", "could not check: \(error.localizedDescription)")
        }
    }

    /// Downloads the installer to the temporary folder and opens it. A file the app downloads itself carries no
    /// quarantine mark, so macOS does not warn about it the way it does for a browser download.
    public func download() async {
        guard case .available(let version) = state, let asset = latestAsset, let url = URL(string: asset.browser_download_url) else { return }
        state = .downloading(version: version)
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            NSWorkspace.shared.open(destination)
            state = .available(version: version)
            DiagnosticLog.write("update", "downloaded \(asset.name) and opened it")
        } catch {
            state = .failed(error.localizedDescription)
            DiagnosticLog.write("update", "could not download: \(error.localizedDescription)")
        }
    }

    nonisolated static func stripV(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Compares dotted version numbers part by part ("1.0.10" is newer than "1.0.9").
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
