import Foundation
import AppKit
import ApplicationServices

/// A log the user can switch on to send along with a bug report.
///
/// It is off by default and writes nothing while off. When on, it keeps what the app sees and decides (status,
/// which earbud is in, what was playing, whether a pause worked, permissions) in a small file that rotates at
/// 1 MB. It never records Bluetooth addresses, the names of other devices or raw packets.
public enum DiagnosticLog {
    public static let defaultsKey = "diagnosticLog"

    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// Lets tests write somewhere else.
    static var directoryOverride: URL?

    public static var directory: URL {
        if let directoryOverride { return directoryOverride }
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Free Buds Manager", isDirectory: true)
    }
    public static var fileURL: URL { directory.appendingPathComponent("diagnostic.log") }
    private static var olderURL: URL { directory.appendingPathComponent("diagnostic.1.log") }

    private static let maxBytes = 1_000_000
    private static let queue = DispatchQueue(label: "io.github.edufigueiredos.FreeBudsManager.diagnostic-log")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    public static func setEnabled(_ on: Bool) {
        if on {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            startSession(reason: "turned on")
        } else {
            write("log", "turned off")
            queue.sync {} // let the line reach the file before the switch closes it
            UserDefaults.standard.set(false, forKey: defaultsKey)
        }
    }

    /// Writes the header (app, system, permissions). Called when the app starts with the log on, and when it is
    /// switched on.
    public static func startSession(reason: String = "app started") {
        guard isEnabled else { return }
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        var uts = utsname()
        uname(&uts)
        let machine = withUnsafeBytes(of: &uts.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        write("session", "\(reason) · Free Buds Manager \(version) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(machine) · locale \(Locale.current.identifier)")
        write("session", "Accessibility allowed: \(AXIsProcessTrusted())")
    }

    public static func write(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(stamp.string(from: Date())) [\(category)] \(message())\n"
        queue.async { append(line) }
    }

    /// Everything the log holds, oldest first.
    public static func contents() -> String {
        queue.sync {
            [olderURL, fileURL]
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .joined()
        }
    }

    public static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: olderURL)
        }
    }

    // MARK: - File

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
            try? manager.removeItem(at: olderURL)
            try? manager.moveItem(at: fileURL, to: olderURL)
        }
        if !manager.fileExists(atPath: fileURL.path) { manager.createFile(atPath: fileURL.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: fileURL), let data = line.data(using: .utf8) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
