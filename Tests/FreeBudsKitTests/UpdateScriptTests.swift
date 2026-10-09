import XCTest
@testable import FreeBudsKit

/// Runs the update helper script against fake apps and a real disk image in a temporary folder.
final class UpdateScriptTests: XCTestCase {
    private var folder: URL!
    private let appName = "Free Buds Manager.app"

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fbm-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("Contents/marker.txt"), atomically: true, encoding: .utf8)
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func makeDMG(containingAppNamed name: String?, marker: String) throws -> URL {
        let source = folder.appendingPathComponent("dmg-source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        if let name { try makeApp(at: source.appendingPathComponent(name), marker: marker) }
        else { try "nothing".write(to: source.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8) }
        let dmg = folder.appendingPathComponent("installer.dmg")
        try run("/usr/bin/hdiutil", ["create", "-volname", "Test", "-srcfolder", source.path, "-format", "UDZO", dmg.path])
        return dmg
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// The fake apps are not code signed, so the signature check line is left out.
    private func runHelper(dmg: URL, app: URL) throws -> Int32 {
        let script = folder.appendingPathComponent("helper.sh")
        let text = UpdateChecker.helperScript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("codesign --verify") }
            .joined(separator: "\n")
        try text.write(to: script, atomically: true, encoding: .utf8)
        // 99999999 is not a running process, so the helper does not wait for anything.
        return try run("/bin/bash", [script.path, "99999999", dmg.path, app.path, "0", folder.appendingPathComponent("update.log").path, "0"])
    }

    func testReplacesTheAppAndCleansUp() throws {
        let app = folder.appendingPathComponent("Applications").appendingPathComponent(appName)
        try makeApp(at: app, marker: "old")
        let dmg = try makeDMG(containingAppNamed: appName, marker: "new")

        XCTAssertEqual(try runHelper(dmg: dmg, app: app), 0)

        XCTAssertEqual(marker(of: app), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path + ".old"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path + ".update"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dmg.path), "the installer is deleted afterwards")
    }

    func testKeepsTheOldAppWhenTheInstallerIsWrong() throws {
        let app = folder.appendingPathComponent("Applications").appendingPathComponent(appName)
        try makeApp(at: app, marker: "old")
        let dmg = try makeDMG(containingAppNamed: nil, marker: "")

        XCTAssertNotEqual(try runHelper(dmg: dmg, app: app), 0)

        XCTAssertEqual(marker(of: app), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path + ".update"))
    }
}
