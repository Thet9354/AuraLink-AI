//
//  AudioFeatures.swift
//  AuraLink AI
//
//  Per-window acoustic features extracted by the DSP stage. Framework-free `Sendable` value type.
//

nonisolated struct AudioFeatures: Sendable {
    /// Short-time RMS energy in decibels (≤ 0; quieter is more negative).
    var energyDB: Float
    /// Zero-crossing rate in [0,1] — a cheap voiced/fricative discriminator.
    var zeroCrossingRate: Float
    /// Estimated fundamental frequency (pitch) in Hz, or nil when unvoiced/silent.
    var f0Hz: Float?
    /// Voice-activity decision for this window.
    var isVoiced: Bool
    /// Window center time, seconds on the capture clock.
    var timeSeconds: Double
}
