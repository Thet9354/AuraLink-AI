//
//  GestureSegmenter.swift
//  AuraLink AI
//
//  Turns the continuous feature stream into recognizable sign windows using a SETTLE-triggered
//  model: a sign is recognized the moment the hand holds still, using the settled handshape itself.
//
//      hand appears → accumulate a rolling window
//      motion drops below `stillThreshold` for `settleSeconds` → EMIT the window (once)
//      motion rises above `moveThreshold` → re-arm for the next sign
//      hand leaves → reset
//
//  Why settle-triggered (not motion-in / pause-out): people show a sign and briefly HOLD it. A
//  motion-gated segmenter would capture only the entry motion and trim away the held handshape —
//  the actual sign — giving unreliable matches, and a purely static hold would never trigger. This
//  model recognizes the stable pose, works whether the sign is dynamic or held, and fires promptly.
//
//  `moveThreshold` > `stillThreshold` is the hysteresis that emits exactly once per hold.
//  Timing is in SECONDS from frame timestamps, so it is identical at any pose frame rate.
//
//  Pure value-type state machine — owned by an actor, fully unit-testable with synthetic frames.
//

nonisolated struct GestureSegmenter {

    struct Config: Sendable {
        /// Motion energy below this means the hand is settling toward a hold.
        var stillThreshold: Float = 0.40
        /// Motion energy above this re-arms the segmenter for the next sign (a deliberate move).
        var moveThreshold: Float = 0.70
        /// How long motion must stay below `stillThreshold` before the hold is recognized.
        var settleSeconds: Double = 0.14
        /// Trailing time window of hand-present frames included in the recognized segment.
        var windowSeconds: Double = 0.5
        /// Minimum frames for a meaningful DTW comparison.
        var minFrames: Int = 4

        init() {}
    }

    let config: Config
    private var window: [FeatureVector] = []
    private var lowStart: Double?            // when the current below-still streak began
    private var armed = true                 // may we emit for the current hold?

    init(config: Config = Config()) {
        self.config = config
    }

    /// Instantaneous motion energy of a frame: for each valid hand, wrist speed (movement path)
    /// plus mean finger-joint speed (articulation); the busier hand wins. Rest frames score ~0.
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
            let shapeMean = shapeSum / Float(Layout.jointsPerHand)
            return wristSpeed + shapeMean
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
        let handPresent = frame.leftHandValid || frame.rightHandValid
        let t = frame.timeSeconds

        guard handPresent else {
            // Hand gone: drop the hold and re-arm for the next appearance.
            window.removeAll()
            lowStart = nil
            armed = true
            return nil
        }

        // Maintain a rolling window of the most recent hand-present frames.
        window.append(frame)
        while let first = window.first, t - first.timeSeconds > config.windowSeconds {
            window.removeFirst()
        }

        let energy = Self.motionEnergy(of: frame)

        if energy >= config.moveThreshold {
            // A deliberate move: this begins a (new) sign; allow the next hold to emit.
            armed = true
            lowStart = nil
            return nil
        }

        if energy < config.stillThreshold {
            if lowStart == nil { lowStart = t }
            if armed,
               t - (lowStart ?? t) >= config.settleSeconds,
               window.count >= config.minFrames,
               let first = window.first, let last = window.last {
                armed = false          // emit once per hold
                return GestureSegment(frames: window,
                                      startSeconds: first.timeSeconds,
                                      endSeconds: last.timeSeconds,
                                      closedReason: .pause)
            }
        } else {
            // Between still and move: transitioning, neither settling nor re-arming.
            lowStart = nil
        }
        return nil
    }

    /// Abandon any in-progress hold (e.g. capture stopped).
    mutating func reset() {
        window.removeAll()
        lowStart = nil
        armed = true
    }
}
