//
//  ProsodyEnvelope.swift
//  AuraLink AI
//
//  The cross-modal bridge: an acoustic window reduced to haptic control parameters, so a Deaf user
//  can FEEL a speaker's emphasis and intonation — information captions discard entirely.
//

nonisolated struct HapticParameters: Sendable, Equatable {
    /// Haptic intensity in [0,1] (mapped from loudness).
    var intensity: Float
    /// Haptic sharpness in [0,1] (mapped from pitch).
    var sharpness: Float

    static let silent = HapticParameters(intensity: 0, sharpness: 0)
}

nonisolated struct ProsodyEnvelope: Sendable {
    var energyDB: Float
    var f0Hz: Float?
    var voiced: Bool
    var parameters: HapticParameters
    var timeSeconds: Double
}
