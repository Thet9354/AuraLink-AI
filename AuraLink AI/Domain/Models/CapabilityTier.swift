//
//  CapabilityTier.swift
//  AuraLink AI
//
//  The single source of truth for what the app is allowed to do on the current device.
//
//  AuraLink supports a range of hardware (A14 → A17+) via a quality ladder. A device is
//  classified into a `DeviceRung` at launch; that picks a *baseline* `CapabilityTier`. The
//  thermal/battery/memory governor (Phase 5) may only push the effective tier DOWN from this
//  baseline — never up. The UI reads `FeatureFlags` so it never offers a feature the current
//  device cannot sustain.
//
//  These are pure Domain value types: no framework imports, explicitly `nonisolated` so they
//  cross actor boundaries freely (the project default actor isolation is `MainActor`).
//

import Foundation

/// Device capability rung, ordered lowest → highest. `Comparable` so the governor can take a
/// `min` across ceilings.
nonisolated enum DeviceRung: Int, Sendable, Comparable, CaseIterable {
    case a14floor = 0   // A13/A14-class (iPhone 11–12): distilled model, 30 fps pose
    case a15 = 1        // A15/A16-class (iPhone 13–14): full model, no predictive head
    case a17plus = 2    // A17 Pro / A18+ (iPhone 15 Pro–16): full model, predictive head, LiDAR

    static func < (lhs: DeviceRung, rhs: DeviceRung) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which sign-recognition model weights to load for a tier.
nonisolated enum ModelVariant: String, Sendable {
    case full
    case distilled
}

/// Feature availability for a tier. The UI gates on this — a disabled feature is never surfaced.
nonisolated struct FeatureFlags: Sendable, Equatable {
    /// Autoregressive gesture-completion prediction to cut perceived latency (a17plus only).
    var predictivePreemption: Bool
    /// Use LiDAR depth to disambiguate sound-source distance (Pro devices only).
    var lidarSoundDepth: Bool
    /// Full audio-prosody → haptic mapping vs. a reduced pattern set.
    var fullHapticProsody: Bool
    /// Whether scene-change narration runs continuously or only on demand.
    var sceneNarration: SceneNarration

    nonisolated enum SceneNarration: Sendable, Equatable { case continuous, onDemand }
}

/// Frame-rate ceilings for the two sampling loops. Pose sampling is cheap and kept high for
/// smoothness; inference is throttled to preserve the thermal/battery envelope.
nonisolated struct FpsCaps: Sendable, Equatable {
    var poseSampleHz: Int
    var signInferenceHz: Int
}

/// The resolved capability profile for a device/state. `Equatable` so the governor can detect
/// and log real transitions (and drive a HUD badge).
nonisolated struct CapabilityTier: Sendable, Equatable {
    var rung: DeviceRung
    var modelVariant: ModelVariant
    var features: FeatureFlags
    var fpsCaps: FpsCaps

    /// The baseline (best-case) tier for a rung, before any thermal/battery/memory de-rating.
    static func baseline(for rung: DeviceRung) -> CapabilityTier {
        switch rung {
        case .a17plus:
            return CapabilityTier(
                rung: .a17plus,
                modelVariant: .full,
                features: FeatureFlags(predictivePreemption: true,
                                       lidarSoundDepth: true,
                                       fullHapticProsody: true,
                                       sceneNarration: .continuous),
                fpsCaps: FpsCaps(poseSampleHz: 60, signInferenceHz: 30))
        case .a15:
            return CapabilityTier(
                rung: .a15,
                modelVariant: .full,
                features: FeatureFlags(predictivePreemption: false,
                                       lidarSoundDepth: false,
                                       fullHapticProsody: true,
                                       sceneNarration: .continuous),
                fpsCaps: FpsCaps(poseSampleHz: 60, signInferenceHz: 20))
        case .a14floor:
            return CapabilityTier(
                rung: .a14floor,
                modelVariant: .distilled,
                features: FeatureFlags(predictivePreemption: false,
                                       lidarSoundDepth: false,
                                       fullHapticProsody: false,
                                       sceneNarration: .onDemand),
                fpsCaps: FpsCaps(poseSampleHz: 30, signInferenceHz: 12))
        }
    }

    /// Human-readable badge for the HUD (e.g. "A17+ · Full").
    var badge: String {
        let rungLabel: String
        switch rung {
        case .a17plus: rungLabel = "A17+"
        case .a15: rungLabel = "A15"
        case .a14floor: rungLabel = "A14"
        }
        return "\(rungLabel) · \(modelVariant.rawValue.capitalized)"
    }
}
