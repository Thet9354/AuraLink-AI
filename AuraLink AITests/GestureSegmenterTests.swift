//
//  GestureSegmenterTests.swift
//  AuraLink AITests
//
//  Phase 3 gate (settle-triggered, wrist-position model): a sign is recognized when the wrist holds
//  its position. Emits once per hold, re-arms when the hand moves to a new position, ignores
//  no-hand frames, continuous motion, and too-brief holds.
//

import Testing
import simd
@testable import AuraLink_AI

struct GestureSegmenterTests {

    private let fps = 30.0

    /// Feeds a wrist trajectory (nil = hand absent) at 30 fps; returns emitted segments.
    private func run(_ wrists: [SIMD2<Float>?],
                     config: GestureSegmenter.Config = .init()) -> [GestureSegment] {
        var seg = GestureSegmenter(config: config)
        var out: [GestureSegment] = []
        for (i, w) in wrists.enumerated() {
            let t = Double(i) / fps
            let frame = w.map { FeatureFactory.frame(seed: 1, wristSpeed: 0, time: t, seq: UInt64(i), wrist: $0) }
                ?? FeatureFactory.empty(time: t, seq: UInt64(i))
            if let s = seg.ingest(frame) { out.append(s) }
        }
        return out
    }

    private func held(_ n: Int, at p: SIMD2<Float> = SIMD2(0.5, 0.5)) -> [SIMD2<Float>?] {
        Array(repeating: p, count: n)
    }
    private func moving(_ n: Int, from a: SIMD2<Float>, to b: SIMD2<Float>) -> [SIMD2<Float>?] {
        (0..<n).map { i in a + (b - a) * (Float(i) / Float(max(n - 1, 1))) }
    }
    private func absent(_ n: Int) -> [SIMD2<Float>?] { Array(repeating: nil, count: n) }

    @Test func heldHandEmitsOnceAfterSettle() {
        let segments = run(held(15))
        #expect(segments.count == 1)                       // once, not per-frame
        #expect((segments.first?.frameCount ?? 0) >= 3)
    }

    @Test func noHandNeverEmits() {
        #expect(run(absent(20)).isEmpty)
    }

    @Test func dynamicSignThenHoldEmits() {
        // Move the hand into position, then hold: recognized once it settles.
        let segments = run(moving(8, from: SIMD2(0.3, 0.5), to: SIMD2(0.6, 0.5)) + held(10, at: SIMD2(0.6, 0.5)))
        #expect(segments.count == 1)
    }

    @Test func reArmsForTheNextSignAfterMoving() {
        // Hold (emit) → move to a new position (re-arm) → hold (emit again).
        let sequence = held(10, at: SIMD2(0.4, 0.5))
            + moving(6, from: SIMD2(0.4, 0.5), to: SIMD2(0.75, 0.5))
            + held(10, at: SIMD2(0.75, 0.5))
        #expect(run(sequence).count == 2)
    }

    @Test func briefHoldDoesNotEmit() {
        // Holds of 2 frames (~0.067 s < 0.15 s), separated by motion — never settles.
        let sequence = moving(6, from: SIMD2(0.2, 0.5), to: SIMD2(0.5, 0.5))
            + held(2, at: SIMD2(0.5, 0.5))
            + moving(6, from: SIMD2(0.5, 0.5), to: SIMD2(0.8, 0.5))
            + held(2, at: SIMD2(0.8, 0.5))
        #expect(run(sequence).isEmpty)
    }

    @Test func continuousMotionNeverSettles() {
        #expect(run(moving(30, from: SIMD2(0.15, 0.5), to: SIMD2(0.9, 0.5))).isEmpty)
    }

    @Test func handLeavingResetsTheHold() {
        // Emit on the first hold, hand leaves, returns and holds → emits again.
        #expect(run(held(10) + absent(4) + held(10)).count == 2)
    }

    @Test func twoHandedSettlesOnlyWhenBothHandsHold() {
        // Right hand held throughout; left hand moving for the first stretch, then held.
        var seg = GestureSegmenter()
        var emits = 0
        for i in 0..<24 {
            let t = Double(i) / fps
            // Left wrist keeps moving for the first 12 frames, then holds.
            let leftX: Float = i < 12 ? 0.2 + Float(i) * 0.03 : 0.6
            let left = SIMD2<Float>(leftX, 0.5)
            let frame = FeatureFactory.frame(seed: 1, wristSpeed: 0, time: t, seq: UInt64(i),
                                             wrist: SIMD2(0.4, 0.5), secondaryWrist: left)
            if seg.ingest(frame) != nil { emits += 1 }
        }
        #expect(emits == 1)   // did not fire while the left hand was still moving
    }

    @Test func smallWristJitterStillSettles() {
        // A held hand with sub-stillRadius jitter must still be recognized (the real-world case).
        let jittered: [SIMD2<Float>?] = (0..<15).map { i in
            let x: Float = 0.5 + Float(i % 3) * 0.01
            let y: Float = 0.5 - Float(i % 2) * 0.01                     // ≤0.02 wander
            return SIMD2<Float>(x, y)
        }
        #expect(run(jittered).count == 1)
    }
}
