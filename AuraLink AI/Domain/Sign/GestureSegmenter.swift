//
//  GestureSegmenter.swift
//  AuraLink AI
//
//  Turns the continuous feature stream into recognizable sign windows using a SETTLE-triggered
//  model: a sign is recognized the moment the hand holds still, using the settled handshape itself.
//
//      hand appears → accumulate a rolling window
//      wrist holds within `stillRadius` for `settleSeconds` → EMIT the window (once)
//      wrist moves `moveRadius` from the last emit → re-arm for the next sign
//      hand leaves → reset
//
//  Stillness is judged by the WRIST'S POSITION IN SPACE, not per-frame joint velocity. Vision's
//  finger-joint estimates jitter a few pixels each frame; dividing that by the frame interval makes
//  a perfectly still hand look like fast motion, so a velocity-based settle never fires. The wrist's
//  absolute position, by contrast, is stable when a sign is held — and "the hand is holding a
//  position" is exactly what showing a sign is.
//
//  `moveRadius` > `stillRadius` is the hysteresis that emits exactly once per hold. Timing is in
//  seconds from frame timestamps, so behavior is identical at any pose frame rate.
//
//  Pure value-type state machine — owned by an actor, fully unit-testable with synthetic frames.
//

import simd

nonisolated struct GestureSegmenter {

    struct Config: Sendable {
        /// The wrist may wander within this radius (image-normalized) and still count as "held".
        var stillRadius: Float = 0.05
        /// Moving this far from the last recognized position re-arms for the next sign.
        var moveRadius: Float = 0.10
        /// How long the wrist must hold still before the sign is recognized.
        var settleSeconds: Double = 0.15
        /// Trailing time window of hand-present frames included in the recognized segment.
        var windowSeconds: Double = 0.5
        /// Minimum frames (within the settle window) for a meaningful DTW comparison.
        var minFrames: Int = 3

        init() {}
    }

    let config: Config
    private var window: [FeatureVector] = []
    private var armed = true
    private var lastEmitWrist: SIMD2<Float>?

    init(config: Config = Config()) {
        self.config = config
    }

    /// Instantaneous motion energy of a frame (wrist speed + mean finger speed). Retained for
    /// diagnostics; the segmenter itself now triggers on wrist-position stability, not this.
    static func motionEnergy(of frame: FeatureVector) -> Float {
        typealias Layout = FeatureExtractor.Layout
        var best: Float = 0

        func handEnergy(valid: Bool, handStart: Int, wristVelocityStart: Int) -> Float {
            guard valid else { return 0 }
            let wx = frame.values[wristVelocityStart]
            let wy = frame.values[wristVelocityStart + 1]
            let wristSpeed = (wx * wx + wy * wy).squareRoot()

            var shapeSum: Float = 0
            let velocityStart = handStart + Layout.positionsPerHand
            for i in 0..<Layout.jointsPerHand {
                let vx = frame.values[velocityStart + i * 2]
                let vy = frame.values[velocityStart + i * 2 + 1]
                shapeSum += (vx * vx + vy * vy).squareRoot()
            }
            return wristSpeed + shapeSum / Float(Layout.jointsPerHand)
        }

        best = max(best, handEnergy(valid: frame.leftHandValid,
                                    handStart: Layout.leftHandStart,
                                    wristVelocityStart: Layout.leftWristVelocityStart))
        best = max(best, handEnergy(valid: frame.rightHandValid,
                                    handStart: Layout.rightHandStart,
                                    wristVelocityStart: Layout.rightWristVelocityStart))
        return best
    }

    /// Feed one frame; returns a recognized segment when a settled hold completes.
    mutating func ingest(_ frame: FeatureVector) -> GestureSegment? {
        guard let wrist = frame.primaryWrist else {
            // Hand gone: drop the hold and re-arm for the next appearance.
            window.removeAll()
            armed = true
            lastEmitWrist = nil
            return nil
        }

        let t = frame.timeSeconds
        window.append(frame)
        while let first = window.first, t - first.timeSeconds > config.windowSeconds {
            window.removeFirst()
        }

        // Re-arm once the hand has moved clearly away from the last recognized position.
        if let last = lastEmitWrist, simd_distance(wrist, last) > config.moveRadius {
            armed = true
            lastEmitWrist = nil
        }
        guard armed else { return nil }

        // Settled? Every present wrist in the last `settleSeconds` sits within a small box. A
        // two-handed sign only settles when BOTH hands hold still.
        let recent = window.filter { t - $0.timeSeconds <= config.settleSeconds }
        guard recent.count >= config.minFrames else { return nil }
        guard isStable(recent, \.primaryWrist) else { return nil }
        if recent.allSatisfy({ $0.secondaryWrist != nil }), !isStable(recent, \.secondaryWrist) {
            return nil
        }
        guard let first = window.first, let last = window.last else { return nil }

        armed = false
        lastEmitWrist = wrist
        return GestureSegment(frames: window,
                              startSeconds: first.timeSeconds,
                              endSeconds: last.timeSeconds,
                              closedReason: .pause)
    }

    /// Whether a wrist keypath stays within `stillRadius` across the given frames.
    private func isStable(_ frames: [FeatureVector],
                          _ keyPath: KeyPath<FeatureVector, SIMD2<Float>?>) -> Bool {
        let points = frames.compactMap { $0[keyPath: keyPath] }
        guard points.count == frames.count, !points.isEmpty else { return false }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return (xs.max()! - xs.min()!) < config.stillRadius
            && (ys.max()! - ys.min()!) < config.stillRadius
    }

    /// Abandon any in-progress hold (e.g. capture stopped).
    mutating func reset() {
        window.removeAll()
        armed = true
        lastEmitWrist = nil
    }
}
