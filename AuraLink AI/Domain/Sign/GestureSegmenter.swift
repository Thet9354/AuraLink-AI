//
//  GestureSegmenter.swift
//  AuraLink AI
//
//  Bounds candidate signs in the continuous feature stream using motion energy with hysteresis:
//
//      idle ── energy > θ_open for minOpen seconds ──► active
//      active ── energy < θ_close for minClose seconds (pause) ──► close segment
//      active ── maxSegment seconds reached ──► force-close
//
//  Timing is measured in SECONDS from each frame's capture timestamp, NOT in frame counts — so the
//  same behavior holds whether the pose front-end runs at 60, 30, or (under the thermal governor)
//  15 fps. θ_open > θ_close (hysteresis) so jitter can't flap the state. A pre-roll window keeps the
//  frames just before the trigger so the onset isn't clipped. Segments shorter than the minimum are
//  discarded as twitches; the trailing pause frames are trimmed.
//
//  Pure value-type state machine — owned by an actor, fully unit-testable with synthetic frames.
//

nonisolated struct GestureSegmenter {

    struct Config: Sendable {
        /// Energy (image-normalized units/second) that opens a segment. Above resting hand jitter.
        var openThreshold: Float = 0.8
        /// Energy below which a frame counts as rest. Must be < openThreshold (hysteresis).
        var closeThreshold: Float = 0.35
        /// Sustained energetic time required to open (rejects single-frame spikes).
        var minOpenSeconds: Double = 0.08
        /// Sustained rest time required to close — the pause that confirms a sign ended. This is the
        /// dominant contributor to perceived glass-to-caption latency; kept short but safe.
        var minCloseSeconds: Double = 0.10
        /// Segments shorter than this (after trimming) are discarded as twitches.
        var minSegmentSeconds: Double = 0.20
        /// Absolute floor of frames a segment needs for a meaningful DTW comparison.
        var minSegmentFrames: Int = 4
        /// Force-close bound — no sign lasts this long.
        var maxSegmentSeconds: Double = 5.0
        /// Time window kept before the open trigger so the sign onset is included.
        var preRollSeconds: Double = 0.15

        init() {}
    }

    private enum State {
        case idle
        case active
    }

    let config: Config
    private var state: State = .idle
    private var preRoll: [FeatureVector] = []
    private var aboveStart: Double?          // when the current above-open streak began
    private var belowStart: Double?          // when the current below-close (rest) streak began
    private var frames: [FeatureVector] = []

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

    /// Feed one frame; returns a closed segment when one completes.
    mutating func ingest(_ frame: FeatureVector) -> GestureSegment? {
        let energy = Self.motionEnergy(of: frame)
        let t = frame.timeSeconds

        switch state {
        case .idle:
            appendPreRoll(frame, now: t)
            if energy >= config.openThreshold {
                if aboveStart == nil { aboveStart = t }
                if t - (aboveStart ?? t) >= config.minOpenSeconds {
                    frames = preRoll                 // seed with the onset
                    state = .active
                    aboveStart = nil
                    belowStart = nil
                }
            } else {
                aboveStart = nil
            }
            return nil

        case .active:
            frames.append(frame)

            if let first = frames.first, t - first.timeSeconds >= config.maxSegmentSeconds {
                return close(reason: .maxLength)
            }

            if energy < config.closeThreshold {
                if belowStart == nil { belowStart = t }
                if t - (belowStart ?? t) >= config.minCloseSeconds {
                    return close(reason: .pause)
                }
            } else {
                belowStart = nil
            }
            return nil
        }
    }

    /// Abandon any in-progress segment (e.g. capture stopped).
    mutating func reset() {
        state = .idle
        aboveStart = nil
        belowStart = nil
        frames.removeAll()
        preRoll.removeAll()
    }

    private mutating func appendPreRoll(_ frame: FeatureVector, now t: Double) {
        preRoll.append(frame)
        while let first = preRoll.first, t - first.timeSeconds > config.preRollSeconds {
            preRoll.removeFirst()
        }
    }

    private mutating func close(reason: GestureSegment.ClosedReason) -> GestureSegment? {
        // On a pause close, drop the trailing rest frames that only served the close dwell.
        let trimmed: [FeatureVector]
        if reason == .pause, let below = belowStart {
            trimmed = frames.filter { $0.timeSeconds < below }
        } else {
            trimmed = frames
        }

        state = .idle
        aboveStart = nil
        belowStart = nil
        frames.removeAll()
        preRoll.removeAll()

        guard let first = trimmed.first, let last = trimmed.last,
              trimmed.count >= config.minSegmentFrames,
              last.timeSeconds - first.timeSeconds >= config.minSegmentSeconds else {
            return nil   // a twitch, not a sign
        }
        return GestureSegment(frames: trimmed,
                              startSeconds: first.timeSeconds,
                              endSeconds: last.timeSeconds,
                              closedReason: reason)
    }
}
