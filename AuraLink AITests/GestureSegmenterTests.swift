//
//  GestureSegmenterTests.swift
//  AuraLink AITests
//
//  Phase 3 gate (settle-triggered model): a sign is recognized when the hand holds still. Emits
//  once per hold, re-arms on deliberate motion, ignores no-hand frames and too-brief settles.
//

import Testing
@testable import AuraLink_AI

struct GestureSegmenterTests {

    private let fps = 30.0

    /// Feeds a sequence of (present, energy-driving wristSpeed) frames; returns emitted segments.
    private func run(_ steps: [(present: Bool, speed: Float)],
                     config: GestureSegmenter.Config = .init()) -> [GestureSegment] {
        var seg = GestureSegmenter(config: config)
        var out: [GestureSegment] = []
        for (i, step) in steps.enumerated() {
            let t = Double(i) / fps
            let frame = step.present
                ? FeatureFactory.frame(seed: 1, wristSpeed: step.speed, time: t, seq: UInt64(i))
                : FeatureFactory.empty(time: t, seq: UInt64(i))
            if let s = seg.ingest(frame) { out.append(s) }
        }
        return out
    }

    private func held(_ n: Int) -> [(present: Bool, speed: Float)] { Array(repeating: (true, 0), count: n) }
    private func moving(_ n: Int) -> [(present: Bool, speed: Float)] { Array(repeating: (true, 1.0), count: n) }
    private func absent(_ n: Int) -> [(present: Bool, speed: Float)] { Array(repeating: (false, 0), count: n) }

    @Test func heldHandEmitsOnceAfterSettle() {
        let segments = run(held(15))
        #expect(segments.count == 1)                       // exactly once, not per-frame spam
        #expect((segments.first?.frameCount ?? 0) >= 4)
    }

    @Test func noHandNeverEmits() {
        #expect(run(absent(20)).isEmpty)
    }

    @Test func dynamicSignThenHoldEmits() {
        // Move the hand into position (energy high), then hold: recognized on settle.
        let segments = run(moving(8) + held(10))
        #expect(segments.count == 1)
    }

    @Test func reArmsForTheNextSignAfterMotion() {
        // Hold (emit) → deliberate move (re-arm) → hold (emit again).
        let segments = run(held(10) + moving(6) + held(10))
        #expect(segments.count == 2)
    }

    @Test func briefStillDoesNotEmit() {
        // A settle shorter than settleSeconds (2 frames ≈ 0.067 s < 0.14 s), interrupted by motion.
        let segments = run(moving(6) + held(2) + moving(6) + held(2))
        #expect(segments.isEmpty)
    }

    @Test func continuousMotionNeverSettles() {
        #expect(run(moving(30)).isEmpty)
    }

    @Test func handLeavingResetsTheHold() {
        // Emit on first hold, hand leaves (re-arm), returns and holds → emits again.
        let segments = run(held(10) + absent(4) + held(10))
        #expect(segments.count == 2)
    }

    @Test func motionEnergyIsZeroForEmptyFrame() {
        #expect(GestureSegmenter.motionEnergy(of: FeatureFactory.empty(time: 0, seq: 0)) == 0)
    }
}
