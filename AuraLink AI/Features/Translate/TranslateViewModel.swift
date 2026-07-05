//
//  TranslateViewModel.swift
//  AuraLink AI
//
//  The single `@MainActor` boundary of the system. It drains the pipeline's latest-value slot
//  and projects frozen `CaptionDTO`s into observable UI state. Because it consumes via
//  `await slot.take()`, the main thread is never blocked — it suspends cooperatively while the
//  background actors work, and resumes on the main actor to publish the result.
//

import Foundation
import Observation

@MainActor
@Observable
final class TranslateViewModel {

    private(set) var caption: CaptionDTO?
    private(set) var isRunning = false
    let tier: CapabilityTier

    private let pipeline: any CaptionProducing
    private let speech: SpeechSynthesizer
    private let settings: AppSettings
    private var consumer: Task<Void, Never>?

    init(pipeline: any CaptionProducing,
         tier: CapabilityTier,
         speech: SpeechSynthesizer,
         settings: AppSettings) {
        self.pipeline = pipeline
        self.tier = tier
        self.speech = speech
        self.settings = settings
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let pipeline = self.pipeline
        Task { await pipeline.start() }

        // Consumer loop. Inherits `@MainActor`, so each `take()` suspends the main actor
        // cooperatively (no thread block) and the assignment publishes on the main actor.
        consumer = Task { [weak self] in
            guard let self else { return }
            let slot = pipeline.output
            while !Task.isCancelled {
                guard let latest = await slot.take() else { break }
                self.caption = latest
                if self.settings.speakAloud, let utterance = latest.utterance {
                    self.speech.speak(utterance)   // sign → speech
                }
            }
        }
    }

    func stop() {
        consumer?.cancel()
        consumer = nil
        isRunning = false
        speech.stop()
        let pipeline = self.pipeline
        Task { await pipeline.stop() }
    }
}
