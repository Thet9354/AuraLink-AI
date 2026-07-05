//
//  GovernorTypes.swift
//  AuraLink AI
//
//  Inputs and outputs of the capability governor. Framework-free so the whole thermal/battery/
//  memory adaptation policy is a pure, table-testable value type.
//

/// Mirror of `ProcessInfo.ThermalState`, kept framework-free (the service maps the real one in).
nonisolated enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3
    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why the effective capability is below the device's baseline (drives the HUD badge).
nonisolated enum DegradeReason: String, Sendable {
    case nominal
    case thermal
    case lowPower
    case memory
}

/// The instantaneous signals the governor resolves.
nonisolated struct GovernorInputs: Sendable, Equatable {
    var baseRung: DeviceRung
    var thermal: ThermalLevel
    var lowPowerMode: Bool
    var memoryWarning: Bool

    init(baseRung: DeviceRung,
         thermal: ThermalLevel = .nominal,
         lowPowerMode: Bool = false,
         memoryWarning: Bool = false) {
        self.baseRung = baseRung
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.memoryWarning = memoryWarning
    }
}

/// The governor's resolved capability: which tier to run, whether to drop to captions-only, and why.
nonisolated struct ResolvedCapability: Sendable, Equatable {
    var tier: CapabilityTier
    /// At critical thermal, non-essential work (haptics, predictive head, scene narration) pauses.
    var captionsOnly: Bool
    var reason: DegradeReason

    var rung: DeviceRung { tier.rung }

    /// HUD label, e.g. "A15 · Full" or "A14 · Distilled · thermal".
    var badge: String {
        reason == .nominal ? tier.badge : "\(tier.badge) · \(reason.rawValue)"
    }
}

extension DeviceRung {
    /// The next rung down (floors at `.a14floor`).
    nonisolated func lowered() -> DeviceRung {
        DeviceRung(rawValue: rawValue - 1) ?? .a14floor
    }
}
