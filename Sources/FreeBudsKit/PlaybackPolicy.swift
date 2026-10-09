import Foundation

/// Decides when this Mac's music is paused and resumed from how many earbuds are in the ears.
///
/// * An earbud comes out (the count goes down) while music is playing: pause.
/// * An earbud goes in (the count goes up) and the app paused the music: resume, even if only one is in.
/// * Nothing else resumes: leaving one earbud in after pausing does not, and music the app did not pause is
///   never started.
struct PlaybackPolicy {
    enum Action: Equatable {
        case none
        case pause
        case resume
    }

    /// How long after pausing the app may still resume.
    static let resumeWindow: TimeInterval = 15 * 60

    private var previousCount: Int?
    private(set) var pausedAt: Date?

    /// `isPlaying` is asked only when a pause is being considered.
    mutating func update(earCount: Int, enabled: Bool, now: Date = Date(), isPlaying: () -> Bool) -> Action {
        defer { previousCount = earCount }
        guard enabled else { pausedAt = nil; return .none }
        guard let previous = previousCount else { return .none }

        if earCount < previous {
            // Already paused for this removal (the second earbud coming out): pressing Play/Pause again
            // would start the music.
            guard pausedAt == nil, isPlaying() else { return .none }
            pausedAt = now
            return .pause
        }
        if earCount > previous, let pausedAt {
            if now.timeIntervalSince(pausedAt) > Self.resumeWindow {
                self.pausedAt = nil
                return .none
            }
            return .resume
        }
        return .none
    }

    /// The resume went through (or was given up on).
    mutating func finishedResuming() { pausedAt = nil }

    /// The earbuds went away (in the case, out of range): forget everything, including a pause made earlier.
    /// Otherwise the first earbud to come back would "resume" music the app paused minutes ago, which starts
    /// a video the user has paused by hand since.
    mutating func reset() {
        previousCount = nil
        pausedAt = nil
    }
}
