//
//  GestureSegmenter.swift
//  AuraLink AI
//
//  Bounds candidate signs in the continuous feature stream using motion energy with hysteresis:
//
//      idle ── energy > θ_open for N_open frames ──► active
//      active ── energy < θ_close for N_close frames (pause) ──► close segment
//      active ── maxFrames reached ──► force-close
//
//  θ_open > θ_close (hysteresis) so jitter around a single threshold cannot flap the state.
//  A pre-roll ring keeps the frames just before the trigger, so the sign's onset is not clipped.
//  Segments shorter than the minimum are discarded as twitches. Trailing rest frames are trimmed.
//
//  Pure value-type state machine — owned by an actor, fully unit-testable with synthetic frames.
//

nonisolated struct GestureSegmenter {

    struct Config: Sendable {
        /// Energy (image-normalized units/second) that opens a segment. Above resting hand jitter.
        var openThreshold: Float = 0.8
        /// Energy below which a frame counts as rest. Must be < openThreshold (hysteresis).
        var closeThreshold: Float = 0.35
        /// Consecutive energetic frames required to open (rejects single-frame spikes).
        var minOpenFrames: Int = 3
        /// Consecutive rest frames required to close (a deliberate pause, ~0.3 s at 30 Hz).
        var minCloseFrames: Int = 9
        /// Segments shorter than this (after trimming) are discarded as twitches.
        var minSegmentFrames: Int = 8
        /// Force-close bound — no sign lasts this long (~5 s at 30 Hz).
        var maxSegmentFrames: Int = 150
        /// Frames kept before the open trigger so the sign onset is included.
        var preRollFrames: Int = 5

        init() {}
    }

    private enum State {
        case idle
        case active
    }

    let config: Config
    private var state: State = .idle
    private var preRoll: RingBuffer<FeatureVector>
    private var aboveCount = 0
    private var belowCount = 0
    private var frames: [FeatureVector] = []

    init(config: Config = Config()) {
        self.config = config
        preRoll = RingBuffer(capacity: max(config.preRollFrames + config.minOpenFrames, 1))
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

        switch state {
        case .idle:
            preRoll.append(frame)
            if energy >= config.openThreshold {
                aboveCount += 1
                if aboveCount >= config.minOpenFrames {
                    // Open: seed with the pre-roll so the onset isn't clipped.
                    frames = preRoll.elements
                    state = .active
                    aboveCount = 0
                    belowCount = 0
                }
            } else {
                aboveCount = 0
            }
            return nil

        case .active:
            frames.append(frame)

            if frames.count >= config.maxSegmentFrames {
                return close(reason: .maxLength)
            }

            if energy < config.closeThreshold {
                belowCount += 1
                if belowCount >= config.minCloseFrames {
                    return close(reason: .pause)
                }
            } else {
                belowCount = 0
            }
            return nil
        }
    }

    /// Abandon any in-progress segment (e.g. capture stopped).
    mutating func reset() {
        state = .idle
        aboveCount = 0
        belowCount = 0
        frames.removeAll()
        preRoll.removeAll()
    }

    private mutating func close(reason: GestureSegment.ClosedReason) -> GestureSegment? {
        // Trim the trailing rest frames that only served the close dwell.
        let trimmed = reason == .pause ? Array(frames.dropLast(belowCount)) : frames
        state = .idle
        aboveCount = 0
        belowCount = 0
        frames.removeAll()
        preRoll.removeAll()

        guard trimmed.count >= config.minSegmentFrames,
              let first = trimmed.first, let last = trimmed.last else {
            return nil   // a twitch, not a sign
        }
        return GestureSegment(frames: trimmed,
                              startSeconds: first.timeSeconds,
                              endSeconds: last.timeSeconds,
                              closedReason: reason)
    }
}
