//
//  HapticsActor.swift
//  AuraLink AI
//
//  The cross-modal haptic channel. Runs a single long-lived CONTINUOUS haptic event whose
//  intensity and sharpness are modulated live from speech prosody — so a Deaf user physically
//  feels loudness and pitch as it happens — and plays discrete TRANSIENT patterns for sound
//  events, ranked by urgency.
//
//  The engine is health-checked and rebuilt on reset/stop (Taptic engines are killed by system
//  pressure); the continuous player is recreated on rebuild. No-ops safely where haptics are
//  unsupported (Simulator, iPad).
//

import CoreHaptics

actor HapticsActor {

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var prosodyPlayer: CHHapticAdvancedPatternPlayer?
    private var running = false
    private var enabled = true

    /// Enable/disable all haptic output (user preference). Disabling silences the prosody channel.
    func setEnabled(_ isEnabled: Bool) {
        enabled = isEnabled
        if !isEnabled { updateProsody(.silent) }
    }

    func start() async {
        guard supportsHaptics, !running else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                Task { await self?.rebuild() }
            }
            engine.stoppedHandler = { _ in }   // rebuilt lazily on next use via rebuild()
            try await engine.start()
            self.engine = engine
            try startProsodyPlayer()
            running = true
        } catch {
            engine = nil
            running = false
        }
    }

    func stop() {
        try? prosodyPlayer?.stop(atTime: CHHapticTimeImmediate)
        prosodyPlayer = nil
        engine?.stop()
        engine = nil
        running = false
    }

    /// Modulate the continuous prosody haptic. Cheap enough to call ~20×/second.
    func updateProsody(_ parameters: HapticParameters) {
        guard running, enabled, let player = prosodyPlayer else { return }
        let dynamics = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: parameters.intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: parameters.sharpness, relativeTime: 0)
        ]
        try? player.sendParameters(dynamics, atTime: CHHapticTimeImmediate)
    }

    /// Play a discrete alert pattern for a sound event; more taps + stronger for higher urgency.
    func playEvent(_ event: SoundEvent) {
        guard running, enabled, let engine else { return }
        let taps: Int
        let intensity: Float
        switch event.urgency {
        case .alert: taps = 3; intensity = 1.0
        case .warn:  taps = 2; intensity = 0.7
        case .info:  taps = 1; intensity = 0.5
        }
        let events = (0..<taps).map { i in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                          ],
                          relativeTime: TimeInterval(i) * 0.12)
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A failed one-shot is non-fatal; the next event will retry on a healthy engine.
        }
    }

    // MARK: - Internals

    private func startProsodyPlayer() throws {
        guard let engine else { return }
        // A very long continuous event, started silent and modulated live via dynamic parameters.
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [
                                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0),
                                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                                  ],
                                  relativeTime: 0,
                                  duration: 60 * 60)
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine.makeAdvancedPlayer(with: pattern)
        player.loopEnabled = true
        try player.start(atTime: CHHapticTimeImmediate)
        prosodyPlayer = player
    }

    private func rebuild() async {
        guard running, let engine else { return }
        do {
            try await engine.start()
            try startProsodyPlayer()
        } catch {
            running = false
        }
    }
}
