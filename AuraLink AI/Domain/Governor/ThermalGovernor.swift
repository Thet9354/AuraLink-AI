//
//  ThermalGovernor.swift
//  AuraLink AI
//
//  The capability governor: resolves live thermal / battery / memory signals into an effective
//  capability tier. Two rules define it:
//
//    1. The effective rung is the MINIMUM of every ceiling — it can only ever be at or below the
//       device's baseline rung, never above.
//    2. HYSTERESIS — downgrade immediately (safety first), but only upgrade after the improved
//       state has held for `upgradeStabilitySeconds`, so a fluctuating thermal sensor can't make
//       the experience flap between tiers.
//
//  Pure, time-parameterized value type (`now` is passed in), so the whole policy — including the
//  hysteresis timing — is deterministically unit-testable.
//

nonisolated struct ThermalGovernor {

    struct Config: Sendable {
        /// An improved state must hold this long before the tier is allowed to rise.
        var upgradeStabilitySeconds: Double = 4
        init() {}
    }

    let config: Config
    let baseRung: DeviceRung
    private var currentRung: DeviceRung
    private var pendingRung: DeviceRung?
    private var pendingSince: Double?

    init(baseRung: DeviceRung, config: Config = Config()) {
        self.baseRung = baseRung
        self.config = config
        self.currentRung = baseRung
    }

    /// The target rung implied by the inputs, as the minimum across all ceilings.
    static func targetRung(_ inputs: GovernorInputs) -> DeviceRung {
        var rung = inputs.baseRung
        switch inputs.thermal {
        case .nominal, .fair:
            break                                   // fair caps fps (tier fpsCaps), not the rung
        case .serious:
            rung = min(rung, inputs.baseRung.lowered())
        case .critical:
            rung = .a14floor                        // floor; captionsOnly also engages
        }
        if inputs.lowPowerMode {
            rung = min(rung, .a15)                  // force ≤ a15 behavior on Low Power Mode
        }
        if inputs.memoryWarning {
            rung = min(rung, inputs.baseRung.lowered())
        }
        return rung
    }

    /// Resolve the effective capability for the given inputs at time `now` (monotonic seconds).
    mutating func resolve(_ inputs: GovernorInputs, now: Double) -> ResolvedCapability {
        let target = Self.targetRung(inputs)

        if target < currentRung {
            // Downgrade immediately.
            currentRung = target
            pendingRung = nil
            pendingSince = nil
        } else if target > currentRung {
            // Upgrade only after the improved target has held long enough.
            if pendingRung != target {
                pendingRung = target
                pendingSince = now
            }
            if let since = pendingSince, now - since >= config.upgradeStabilitySeconds {
                currentRung = target
                pendingRung = nil
                pendingSince = nil
            }
        } else {
            pendingRung = nil
            pendingSince = nil
        }

        return ResolvedCapability(tier: .baseline(for: currentRung),
                                  captionsOnly: inputs.thermal == .critical,
                                  reason: Self.reason(for: inputs))
    }

    /// The current effective rung (for diagnostics/tests).
    var effectiveRung: DeviceRung { currentRung }

    /// The dominant degradation cause, most-severe first.
    static func reason(for inputs: GovernorInputs) -> DegradeReason {
        if inputs.thermal >= .serious { return .thermal }
        if inputs.memoryWarning { return .memory }
        if inputs.lowPowerMode && inputs.baseRung > .a15 { return .lowPower }
        return .nominal
    }
}
