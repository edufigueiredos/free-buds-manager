import XCTest
@testable import FreeBudsKit

final class DiagnosticLogTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fbm-log-test-\(UUID().uuidString)")
        DiagnosticLog.directoryOverride = folder
        UserDefaults.standard.set(false, forKey: DiagnosticLog.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DiagnosticLog.defaultsKey)
        DiagnosticLog.directoryOverride = nil
        try? FileManager.default.removeItem(at: folder)
    }

    func testWritesNothingWhileOff() {
        DiagnosticLog.write("test", "hello")
        XCTAssertEqual(DiagnosticLog.contents(), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: DiagnosticLog.fileURL.path))
    }

    func testRecordsWhileOnAndStopsWhenOff() {
        DiagnosticLog.setEnabled(true)
        DiagnosticLog.write("wear", "left out, right in")
        var text = DiagnosticLog.contents()
        XCTAssertTrue(text.contains("[session]"), text)
        XCTAssertTrue(text.contains("[wear] left out, right in"), text)

        DiagnosticLog.setEnabled(false)
        DiagnosticLog.write("wear", "after off")
        text = DiagnosticLog.contents()
        XCTAssertTrue(text.contains("[log] turned off"), text)
        XCTAssertFalse(text.contains("after off"), text)
    }

    func testClearEmptiesTheLog() {
        DiagnosticLog.setEnabled(true)
        DiagnosticLog.write("x", "y")
        XCTAssertFalse(DiagnosticLog.contents().isEmpty)
        DiagnosticLog.clear()
        XCTAssertEqual(DiagnosticLog.contents(), "")
    }

    func testRotatesWhenTooBig() {
        DiagnosticLog.setEnabled(true)
        let line = String(repeating: "a", count: 1000)
        for _ in 0..<1200 { DiagnosticLog.write("fill", line) }
        let text = DiagnosticLog.contents()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("diagnostic.1.log").path))
        XCTAssertGreaterThan(text.count, 1_000_000)
        XCTAssertLessThan(text.count, 2_100_000)
    }
}
