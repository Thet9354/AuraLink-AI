//
//  SpeechSynthesizer.swift
//  AuraLink AI
//
//  Speaks recognized signs/phrases aloud with `AVSpeechSynthesizer` — fully on-device, so it
//  preserves the zero-network invariant. This completes the sign→SPEECH modality: a Deaf or
//  non-verbal user shows a gesture and the phone talks for them.
//

import AVFoundation

@MainActor
final class SpeechSynthesizer {

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    /// Speak text. Interrupts any in-progress utterance so the latest sign is heard promptly.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
