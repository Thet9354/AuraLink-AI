//
//  ListenViewModel.swift
//  AuraLink AI
//
//  Drives ambient-audio mode: live speech captions, recent sound-event alerts, and a live prosody
//  meter mirroring the haptic intensity/sharpness the user feels.
//

import Foundation
import Observation

@MainActor
@Observable
final class ListenViewModel {

    private(set) var caption: CaptionDTO?
    private(set) var recentEvents: [SoundEvent] = []
    private(set) var prosody: ProsodyEnvelope?
    private(set) var isRunning = false
    private(set) var errorText: String?

    private let listener: AudioListener
    private let settings: AppSettings
    private var captionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var prosodyTask: Task<Void, Never>?

    private let maxEvents = 6

    init(listener: AudioListener, settings: AppSettings) {
        self.listener = listener
        self.settings = settings
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        errorText = nil

        let listener = self.listener
        let hapticsEnabled = settings.hapticsEnabled
        Task { [weak self] in
            do {
                try await listener.start(hapticsEnabled: hapticsEnabled)
            } catch {
                self?.errorText = "Microphone unavailable: \(error)"
                self?.isRunning = false
            }
        }

        captionTask = Task { [weak self] in
            for await caption in listener.captions {
                self?.caption = caption
            }
        }
        eventTask = Task { [weak self] in
            for await event in listener.soundEvents {
                guard let self else { break }
                self.recentEvents.insert(event, at: 0)
                if self.recentEvents.count > self.maxEvents {
                    self.recentEvents.removeLast(self.recentEvents.count - self.maxEvents)
                }
            }
        }
        prosodyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let envelope = await listener.prosody.take() else { break }
                self?.prosody = envelope
            }
        }
    }

    func stop() {
        captionTask?.cancel(); captionTask = nil
        eventTask?.cancel(); eventTask = nil
        prosodyTask?.cancel(); prosodyTask = nil
        isRunning = false
        let listener = self.listener
        Task { await listener.stop() }
    }
}
