import AVFoundation
import Foundation

@MainActor
final class SpeechAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenId: String?

    func announceIfNeeded(track: Track?, enabled: Bool) {
        guard enabled, let track else {
            synthesizer.stopSpeaking(at: .immediate)
            lastSpokenId = nil
            return
        }
        guard track.effectiveId != lastSpokenId else { return }
        lastSpokenId = track.effectiveId
        let utterance = AVSpeechUtterance(string: "\(track.title) by \(track.artist)")
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastSpokenId = nil
    }
}
