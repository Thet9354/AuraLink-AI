//
//  ProsodyMapper.swift
//  AuraLink AI
//
//  Maps acoustic prosody to haptic control parameters:
//    • LOUDNESS (energy dB) → haptic INTENSITY — you feel emphasis and volume.
//    • PITCH (f0 Hz)        → haptic SHARPNESS — you feel intonation (rising questions, stress).
//  Unvoiced/silent windows fade to a dull, low buzz rather than snapping to zero, so the haptic
//  track feels continuous. Both mappings are monotonic (verified in tests).
//

nonisolated enum ProsodyMapper {

    /// Loudness window mapped to full intensity range. Below `minDB` → silent; above `maxDB` → max.
    static let minDB: Float = -50
    static let maxDB: Float = -12

    /// Pitch window mapped to full sharpness range (roughly the speaking-voice span).
    static let minF0: Float = 90
    static let maxF0: Float = 280

    /// Sharpness for voiced-but-pitchless or unvoiced audio (a soft, dull texture).
    static let unvoicedSharpness: Float = 0.15

    static func parameters(energyDB: Float, f0Hz: Float?, voiced: Bool) -> HapticParameters {
        let intensity = normalize(energyDB, from: minDB, to: maxDB)
        let sharpness: Float
        if voiced, let f0 = f0Hz {
            sharpness = normalize(f0, from: minF0, to: maxF0)
        } else {
            sharpness = unvoicedSharpness
        }
        return HapticParameters(intensity: intensity, sharpness: sharpness)
    }

    /// Builds a full envelope (features + haptic params) for one window.
    static func envelope(from features: AudioFeatures) -> ProsodyEnvelope {
        ProsodyEnvelope(energyDB: features.energyDB,
                        f0Hz: features.f0Hz,
                        voiced: features.isVoiced,
                        parameters: parameters(energyDB: features.energyDB,
                                               f0Hz: features.f0Hz,
                                               voiced: features.isVoiced),
                        timeSeconds: features.timeSeconds)
    }

    /// Clamped linear map to [0,1].
    private static func normalize(_ value: Float, from lo: Float, to hi: Float) -> Float {
        guard hi > lo else { return 0 }
        return min(1, max(0, (value - lo) / (hi - lo)))
    }
}
