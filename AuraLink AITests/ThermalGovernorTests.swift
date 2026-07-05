//
//  ThermalGovernorTests.swift
//  AuraLink AITests
//
//  Phase 5 gate: the governor only ever de-rates from baseline, picks the minimum across ceilings,
//  and applies hysteresis — downgrade immediately, upgrade only after the improved state holds.
//

import Testing
@testable import AuraLink_AI

struct ThermalGovernorTests {

    private func inputs(_ base: DeviceRung,
                        thermal: ThermalLevel = .nominal,
                        lowPower: Bool = false,
                        memory: Bool = false) -> GovernorInputs {
        GovernorInputs(baseRung: base, thermal: thermal, lowPowerMode: lowPower, memoryWarning: memory)
    }

    @Test func nominalKeepsBaseline() {
        var g = ThermalGovernor(baseRung: .a17plus)
        let r = g.resolve(inputs(.a17plus), now: 0)
        #expect(r.rung == .a17plus)
        #expect(r.reason == .nominal)
        #expect(!r.captionsOnly)
    }

    @Test func seriousThermalDropsOneRungImmediately() {
        var g = ThermalGovernor(baseRung: .a17plus)
        let r = g.resolve(inputs(.a17plus, thermal: .serious), now: 0)
        #expect(r.rung == .a15)
        #expect(r.reason == .thermal)
    }

    @Test func criticalThermalFloorsAndEngagesCaptionsOnly() {
        var g = ThermalGovernor(baseRung: .a17plus)
        let r = g.resolve(inputs(.a17plus, thermal: .critical), now: 0)
        #expect(r.rung == .a14floor)
        #expect(r.captionsOnly)
    }

    @Test func neverRisesAboveBaseline() {
        var g = ThermalGovernor(baseRung: .a14floor)
        // Even at perfect conditions a floor device stays at the floor.
        let r = g.resolve(inputs(.a14floor), now: 100)
        #expect(r.rung == .a14floor)
    }

    @Test func lowPowerModeCapsAtA15() {
        var g = ThermalGovernor(baseRung: .a17plus)
        let r = g.resolve(inputs(.a17plus, lowPower: true), now: 0)
        #expect(r.rung == .a15)
        #expect(r.reason == .lowPower)
    }

    @Test func minimumAcrossCeilingsWins() {
        var g = ThermalGovernor(baseRung: .a17plus)
        // Low power caps at a15, but serious thermal drops a rung below base → a15; memory also.
        let r = g.resolve(inputs(.a17plus, thermal: .serious, lowPower: true, memory: true), now: 0)
        #expect(r.rung == .a15)
        #expect(r.reason == .thermal)   // most-severe cause reported
    }

    @Test func downgradeIsImmediateUpgradeIsDelayed() {
        var g = ThermalGovernor(baseRung: .a17plus)

        // Heat up → immediate drop.
        #expect(g.resolve(inputs(.a17plus, thermal: .serious), now: 0).rung == .a15)

        // Cool down at t=1: not yet upgraded (needs 4 s of stability).
        #expect(g.resolve(inputs(.a17plus, thermal: .nominal), now: 1).rung == .a15)
        // Still holding at t=3.
        #expect(g.resolve(inputs(.a17plus, thermal: .nominal), now: 3).rung == .a15)
        // After the stability window → upgraded back to baseline.
        #expect(g.resolve(inputs(.a17plus, thermal: .nominal), now: 5).rung == .a17plus)
    }

    @Test func fluctuationDuringWindowResetsTheUpgradeTimer() {
        var g = ThermalGovernor(baseRung: .a17plus)
        _ = g.resolve(inputs(.a17plus, thermal: .serious), now: 0)          // dropped to a15
        _ = g.resolve(inputs(.a17plus, thermal: .nominal), now: 1)          // start cool-down timer
        _ = g.resolve(inputs(.a17plus, thermal: .serious), now: 2)          // heat again — reset
        // Only 3 s since the last cool-down began (t=3), not enough yet.
        #expect(g.resolve(inputs(.a17plus, thermal: .nominal), now: 3).rung == .a15)
        // 4 s after the fresh cool-down → upgrade.
        #expect(g.resolve(inputs(.a17plus, thermal: .nominal), now: 7).rung == .a17plus)
    }
}
