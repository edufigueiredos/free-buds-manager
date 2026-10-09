import SwiftUI
import FreeBudsKit

/// Human-readable names for the raw codes the earbuds use. Unknown codes are shown, not hidden.
enum Labels {
    static func ancMode(_ mode: ANCMode) -> LocalizedStringKey {
        switch mode {
        case .off: return "Off"
        case .cancellation: return "Noise cancelling"
        case .awareness: return "Awareness"
        }
    }

    static func cancellationLevel(_ level: CancellationLevel) -> LocalizedStringKey {
        switch level {
        case .comfort: return "Cozy"
        case .normal: return "General"
        case .ultra: return "Ultra"
        case .dynamic: return "Dual engine"
        }
    }

    static func awarenessLevel(_ level: AwarenessLevel) -> LocalizedStringKey {
        switch level {
        case .normal: return "Standard"
        case .voiceBoost: return "Voice"
        case .adaptive: return "Adaptive"
        }
    }

    static func spatialAudio(_ mode: SpatialAudio) -> LocalizedStringKey {
        switch mode {
        case .off: return "Off"
        case .fixed: return "Fixed"
        case .headTracking: return "Head tracking"
        }
    }

    static func equalizer(_ preset: EqualizerPreset) -> LocalizedStringKey {
        switch preset {
        case .adaptive: return "Adaptive EQ"
        case .balanced: return "Balanced"
        case .voice: return "Voice"
        case .bass: return "Bass"
        case .classic: return "Classic"
        case .movie: return "Movie"
        case .podcast: return "Podcast"
        case .games: return "Games"
        case .impact: return "Impact"
        }
    }

    static func soundPreference(_ preference: SoundPreference) -> LocalizedStringKey {
        switch preference {
        case .connectivity: return "Prefer connection stability"
        case .quality: return "Prefer sound quality"
        }
    }

    static func pinch(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.answerCall: return "Answer / end call"
        case GestureCode.rejectCall: return "Reject call"
        case GestureCode.playPause: return "Play / Pause"
        case GestureCode.previousTrack: return "Previous track"
        case GestureCode.nextTrack: return "Next track"
        default: return "Action \(Int(code))"
        }
    }

    static func pinchHold(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.holdAssistant: return "Voice assistant"
        case GestureCode.holdNoiseControl: return "Noise control"
        default: return "Action \(Int(code))"
        }
    }

    static func doubleTap(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.tapPlayPause: return "Play / Pause"
        case GestureCode.tapAnswerCall: return "Answer / end call"
        default: return "Action \(Int(code))"
        }
    }

    static func tripleTap(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.tapNext: return "Next track"
        case GestureCode.tapPrevious: return "Previous track"
        default: return "Action \(Int(code))"
        }
    }

    static func hold(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.pressAssistant: return "Voice assistant"
        case GestureCode.pressNoiseControl: return "Noise control"
        default: return "Action \(Int(code))"
        }
    }

    static func swipe(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case GestureCode.none: return "Nothing"
        case GestureCode.swipeVolume: return "Adjust volume"
        default: return "Action \(Int(code))"
        }
    }

    static func ancCycle(_ code: Int8) -> LocalizedStringKey {
        switch code {
        case 1: return "Off ↔ Noise cancelling"
        case 2: return "Off ↔ Noise cancelling ↔ Awareness"
        case 3: return "Noise cancelling ↔ Awareness"
        case 4: return "Off ↔ Awareness"
        default: return "Mode \(Int(code))"
        }
    }

    static func equalizerName(id: Int, custom: [CustomEqualizer]) -> Text {
        if let preset = EqualizerPreset(rawValue: id) { return Text(equalizer(preset)) }
        if let profile = custom.first(where: { $0.id == id }) { return Text(verbatim: profile.name) }
        return Text("Preset \(id)")
    }
}
