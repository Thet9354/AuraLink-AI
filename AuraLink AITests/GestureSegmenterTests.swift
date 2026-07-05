//
//  GestureSegmenterTests.swift
//  AuraLink AITests
//
//  Phase 3 gate: motion-energy segmentation with hysteresis — opens on sustained motion, closes
//  on a pause, rejects twitches, force-closes overlong runs, and includes the onset via pre-roll.
//

import Testing
@testable import AuraLink_AI

struct GestureSegmenterTests {

    /// Feeds a frame sequence and returns all segments produced.
    private func run(_ frames: [FeatureVector], config: GestureSegmenter.Config = .init()) -> [GestureSegment] {
        var segmenter = GestureSegmenter(config: config)
        var out: [GestureSegment] = []
        for f in frames {
            if let segment = segmenter.ingest(f) { out.append(segment) }
        }
        return out
    }

    /// rest… → motion… → rest… yields exactly one segment.
    @Test func restMotionRestProducesOneSegment() {
        var frames: [FeatureVector] = []
        var seq: UInt64 = 0
        func push(_ f: (Double, UInt64) -> FeatureVector) { frames.append(f(Double(seq) / 30, seq)); seq += 1 }

        for _ in 0..<10 { push { FeatureFactory.rest(seed: 1, time: $0, seq: $1) } }
        for _ in 0..<25 { push { FeatureFactory.frame(seed: 1, wristSpeed: 1.5, time: $0, seq: $1) } }
        for _ in 0..<15 { push { FeatureFactory.rest(seed: 1, time: $0, seq: $1) } }

        let segments = run(frames)
        #expect(segments.count == 1)
        #expect(segments.first?.closedReason == .pause)
        #expect((segments.first?.frameCount ?? 0) >= 20)
    }

    /// A single high-energy frame amid rest never opens a segment (min-open guard).
    @Test func singleSpikeDoesNotOpen() {
        var frames: [FeatureVector] = []
        var seq: UInt64 = 0
        for _ in 0..<10 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }
        frames.append(FeatureFactory.frame(seed: 1, wristSpeed: 3.0, time: Double(seq)/30, seq: seq)); seq += 1
        for _ in 0..<10 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }

        #expect(run(frames).isEmpty)
    }

    /// A brief motion burst shorter than the minimum segment duration is discarded as a twitch.
    @Test func shortBurstIsRejectedAsTwitch() {
        var config = GestureSegmenter.Config()
        config.minSegmentSeconds = 0.5
        var frames: [FeatureVector] = []
        var seq: UInt64 = 0
        for _ in 0..<8 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }
        for _ in 0..<6 { frames.append(FeatureFactory.frame(seed: 1, wristSpeed: 1.5, time: Double(seq)/30, seq: seq)); seq += 1 }
        for _ in 0..<15 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }

        #expect(run(frames, config: config).isEmpty)
    }

    /// Continuous motion beyond the max bound force-closes.
    @Test func overlongMotionForceCloses() {
        var config = GestureSegmenter.Config()
        config.maxSegmentSeconds = 1.0            // ~30 frames at 30 fps
        var frames: [FeatureVector] = []
        var seq: UInt64 = 0
        for _ in 0..<6 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }
        for _ in 0..<80 { frames.append(FeatureFactory.frame(seed: 1, wristSpeed: 1.5, time: Double(seq)/30, seq: seq)); seq += 1 }

        let segments = run(frames, config: config)
        #expect(segments.count >= 1)
        #expect(segments.first?.closedReason == .maxLength)
        // Duration is bounded even though the motion ran much longer.
        #expect((segments.first?.durationSeconds ?? 0) <= config.maxSegmentSeconds + 0.05)
    }

    /// Hysteresis: energy hovering between close and open thresholds does not flap the segment
    /// closed prematurely.
    @Test func energyBetweenThresholdsDoesNotFlap() {
        var frames: [FeatureVector] = []
        var seq: UInt64 = 0
        let config = GestureSegmenter.Config()   // open 0.8, close 0.35
        for _ in 0..<8 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }
        for _ in 0..<6 { frames.append(FeatureFactory.frame(seed: 1, wristSpeed: 1.5, time: Double(seq)/30, seq: seq)); seq += 1 }
        // Mid-energy (0.5): above close, below open — should keep the segment open.
        for _ in 0..<20 { frames.append(FeatureFactory.frame(seed: 1, wristSpeed: 0.5, time: Double(seq)/30, seq: seq)); seq += 1 }
        for _ in 0..<15 { frames.append(FeatureFactory.rest(seed: 1, time: Double(seq)/30, seq: seq)); seq += 1 }

        let segments = run(frames, config: config)
        #expect(segments.count == 1)
        #expect((segments.first?.frameCount ?? 0) >= 25)   // the mid-energy stretch stayed in
    }

    @Test func motionEnergyIsZeroForEmptyFrame() {
        let energy = GestureSegmenter.motionEnergy(of: FeatureFactory.empty(time: 0, seq: 0))
        #expect(energy == 0)
    }
}
