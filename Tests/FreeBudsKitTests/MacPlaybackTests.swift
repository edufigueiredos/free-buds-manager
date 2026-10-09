import XCTest
@testable import FreeBudsKit

final class MacPlaybackTests: XCTestCase {
    func testCallAppsDoNotCountAsMusic() {
        for bundle in ["com.microsoft.teams2", "us.zoom.xos", "com.apple.FaceTime", "com.apple.avconferenced", "com.cisco.webexmeetingsapp"] {
            XCTAssertFalse(MacPlayback.countsAsMusic(bundle), bundle)
        }
    }

    func testPlayersAndBrowsersCountAsMusic() {
        for bundle in ["com.apple.Music", "com.spotify.client", "com.google.Chrome.helper", "unknown"] {
            XCTAssertTrue(MacPlayback.countsAsMusic(bundle), bundle)
        }
    }

    func testOnlyMusicAndSpotifyArePausedByName() {
        XCTAssertEqual(MacPlayback.scriptablePlayers, ["com.apple.Music", "com.spotify.client"])
    }

    func testNothingPausedMeansNothingToResume() {
        var paused = MacPlayback.PausedMedia()
        XCTAssertTrue(paused.isEmpty)
        paused.byKey = true
        XCTAssertFalse(paused.isEmpty)
        paused = MacPlayback.PausedMedia()
        paused.players = ["com.spotify.client"]
        XCTAssertFalse(paused.isEmpty)
    }
}
