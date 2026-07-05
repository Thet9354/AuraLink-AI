//
//  VoiceActivityDetector.swift
//  AuraLink AI
//
//  Energy-based VAD with an adaptive noise floor. The floor tracks background level (falls quickly
//  toward quiet, rises slowly), and a window is voiced when its energy exceeds the floor by a
//  margin. Adapting to the room means it works in a quiet study and a noisy cafe without retuning.
//
//  Pure value-type state machine; the owning actor holds one instance.
//

nonisolated struct VoiceActivityDetector {

    struct Config: Sendable {
        /// Energy must exceed the noise floor by this many dB to count as voice.
        var marginDB: Float = 10
        /// Adaptation rate toward quieter energies (fast — track the room settling down).
        var fallRate: Float = 0.3
        /// Adaptation rate toward louder energies (slow — don't let speech raise the floor).
        var riseRate: Float = 0.02
        /// Consecutive voiced windows required to latch ON (debounce onsets).
        var onFrames: Int = 2
        /// Consecutive silent windows required to latch OFF (bridge natural pauses).
        var offFrames: Int = 8

        init() {}
    }

    let config: Config
    private var noiseFloorDB: Float
    private var voiced = false
    private var aboveCount = 0
    private var belowCount = 0

    init(config: Config = Config(), initialFloorDB: Float = -55) {
        self.config = config
        self.noiseFloorDB = initialFloorDB
    }

    /// The current adaptive noise floor (dB), for diagnostics.
    var noiseFloor: Float { noiseFloorDB }

    /// Process one window's energy; returns the (debounced) voice-activity decision.
    mutating func process(energyDB: Float) -> Bool {
        // Adapt the floor: quickly toward quieter energy, slowly toward louder.
        if energyDB < noiseFloorDB {
            noiseFloorDB += (energyDB - noiseFloorDB) * config.fallRate
        } else {
            noiseFloorDB += (energyDB - noiseFloorDB) * config.riseRate
        }

        let isLoud = energyDB > noiseFloorDB + config.marginDB
        if isLoud {
            aboveCount += 1
            belowCount = 0
            if aboveCount >= config.onFrames { voiced = true }
        } else {
            belowCount += 1
            aboveCount = 0
            if belowCount >= config.offFrames { voiced = false }
        }
        return voiced
    }
}
