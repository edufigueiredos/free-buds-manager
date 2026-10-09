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
        /// Downloaded and ready to be installed in place of this app.
        case ready(version: String)
        case installing(version: String)
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
    private var downloadedInstaller: URL?

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
            if Self.canInstallInPlace {
                downloadedInstaller = destination
                state = .ready(version: version)
                DiagnosticLog.write("update", "downloaded \(asset.name); ready to install")
            } else {
                // Not writable (or not in a normal place): leave the replacing to the user.
                NSWorkspace.shared.open(destination)
                state = .available(version: version)
                DiagnosticLog.write("update", "downloaded \(asset.name) and opened it (cannot replace the app here)")
            }
        } catch {
            state = .failed(error.localizedDescription)
            DiagnosticLog.write("update", "could not download: \(error.localizedDescription)")
        }
    }

    /// The app can replace itself only when the folder it lives in is writable by the user.
    static var canInstallInPlace: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Quits the app, replaces it with the downloaded version and opens it again. A helper script does the
    /// replacing, because an app cannot replace itself while it runs.
    public func install() {
        guard case .ready(let version) = state, let installer = downloadedInstaller else { return }
        do {
            let script = FileManager.default.temporaryDirectory.appendingPathComponent("fbm-update.sh")
            try Self.helperScript.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs/Free Buds Manager", isDirectory: true)
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), installer.path,
                                 Bundle.main.bundleURL.path, "1", logs.appendingPathComponent("update.log").path]
            try process.run()
            state = .installing(version: version)
            DiagnosticLog.write("update", "installing \(version): the app quits now and the helper replaces it")
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
            DiagnosticLog.write("update", "could not start the installation: \(error.localizedDescription)")
        }
    }

    /// Arguments: the app's process id, the installer (.dmg), the app to replace, whether to open it afterwards
    /// (0 or 1), the log file, seconds to wait before deleting the old version. The old version is kept aside until the new one is in place, and put back if
    /// anything fails.
    static let helperScript = """
    #!/bin/bash
    PID="$1"; DMG="$2"; APP="$3"; LAUNCH="${4:-1}"; LOG="${5:-/dev/null}"; SETTLE="${6:-8}"
    NAME="$(basename "$APP")"
    MP=""
    log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
    fail() {
      log "FAILED: $*"
      if [ -d "$APP.old" ] && [ ! -d "$APP" ]; then mv "$APP.old" "$APP" && log "put the old version back"; fi
      rm -rf "$APP.update"
      if [ -n "$MP" ]; then hdiutil detach "$MP" -quiet 2>/dev/null; fi
      if [ "$LAUNCH" = 1 ]; then open "$APP"; fi
      osascript -e 'display notification "Could not update. The previous version was kept." with title "Free Buds Manager"' 2>/dev/null
      exit 1
    }
    log "waiting for $PID to quit"
    for _ in $(seq 1 80); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
    if kill -0 "$PID" 2>/dev/null; then fail "the app did not quit"; fi
    MP="$(mktemp -d /tmp/fbm-update.XXXXXX)"
    hdiutil attach "$DMG" -nobrowse -readonly -noverify -noautoopen -mountpoint "$MP" >/dev/null 2>&1 || fail "could not open the installer"
    NEW="$MP/$NAME"
    [ -d "$NEW" ] || fail "the installer has no $NAME"
    rm -rf "$APP.update" "$APP.old"
    ditto "$NEW" "$APP.update" || fail "could not copy the new version"
    hdiutil detach "$MP" -quiet 2>/dev/null; rmdir "$MP" 2>/dev/null; MP=""
    codesign --verify --deep --strict "$APP.update" 2>>"$LOG" || fail "the new version failed its signature check"
    mv "$APP" "$APP.old" || fail "could not move the old version aside"
    mv "$APP.update" "$APP" || fail "could not put the new version in place"
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null
    log "installed"
    if [ "$LAUNCH" = 1 ]; then open "$APP"; fi
    sleep "$SETTLE"
    rm -rf "$APP.old"
    rm -f "$DMG"
    log "done"
    """

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
