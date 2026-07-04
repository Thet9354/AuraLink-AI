//
//  FeatureExtractor.swift
//  AuraLink AI
//
//  Turns a `PoseObservation` into the fixed-layout `FeatureVector` used by segmentation and DTW.
//
//  Three complementary feature families, chosen for what ASL actually encodes:
//    • HANDSHAPE  — normalized joint positions (invariant to position/distance/roll).
//    • SHAPE MOTION — velocity of the normalized joints (finger articulation over time).
//    • SIGNING SPACE + PATH — the raw wrist's position relative to the body (signs are located:
//      chin vs chest vs shoulder…) and the raw wrist's velocity (movement path). These use
//      UN-normalized coordinates on purpose: normalization deliberately removes global motion,
//      which is itself a distinguishing component of a sign.
//
//  Pure function over (observation, previous state) → (features, next state); the owning actor
//  holds the state between frames. Fully unit-testable with synthetic poses.
//

import simd

nonisolated enum FeatureExtractor {

    /// Fixed feature layout. Exemplars recorded at enrollment depend on this — bump `version`
    /// on any change and re-record.
    enum Layout {
        static let version = 1
        static let jointsPerHand = HandJoint.count                    // 21
        static let positionsPerHand = jointsPerHand * 2               // 42
        static let velocitiesPerHand = jointsPerHand * 2              // 42
        static let perHand = positionsPerHand + velocitiesPerHand     // 84

        static let leftHandStart = 0
        static let rightHandStart = perHand                           // 84
        static let leftWristBodyStart = perHand * 2                   // 168 (2 values)
        static let rightWristBodyStart = leftWristBodyStart + 2       // 170 (2 values)
        static let leftWristVelocityStart = rightWristBodyStart + 2   // 172 (2 values)
        static let rightWristVelocityStart = leftWristVelocityStart + 2 // 174 (2 values)
        static let leftValidIndex = rightWristVelocityStart + 2       // 176
        static let rightValidIndex = leftValidIndex + 1               // 177
        static let dimension = rightValidIndex + 1                    // 178
    }

    /// Per-hand carry-over between frames, held by the owning actor.
    struct State: Sendable {
        var previousTimeSeconds: Double?
        var previousLeftNormalized: [SIMD2<Float>]?
        var previousRightNormalized: [SIMD2<Float>]?
        var previousLeftWristRaw: SIMD2<Float>?
        var previousRightWristRaw: SIMD2<Float>?

        init() {}
    }

    /// Velocity computation guards against absurd dt (dropped frames, first frame).
    static let minDeltaSeconds = 1.0 / 120.0

    static func extract(from observation: PoseObservation,
                        state: State) -> (FeatureVector, State) {
        var values = [Float](repeating: 0, count: Layout.dimension)
        var next = State()
        next.previousTimeSeconds = observation.timeSeconds

        let dt = Float(max(observation.timeSeconds - (state.previousTimeSeconds ?? observation.timeSeconds),
                           minDeltaSeconds))

        let left = processHand(.left, observation: observation,
                               previousNormalized: state.previousLeftNormalized,
                               previousWristRaw: state.previousLeftWristRaw,
                               hadPreviousTime: state.previousTimeSeconds != nil,
                               dt: dt,
                               handStart: Layout.leftHandStart,
                               wristBodyStart: Layout.leftWristBodyStart,
                               wristVelocityStart: Layout.leftWristVelocityStart,
                               into: &values)
        next.previousLeftNormalized = left.normalized
        next.previousLeftWristRaw = left.wristRaw
        values[Layout.leftValidIndex] = left.valid ? 1 : 0

        let right = processHand(.right, observation: observation,
                                previousNormalized: state.previousRightNormalized,
                                previousWristRaw: state.previousRightWristRaw,
                                hadPreviousTime: state.previousTimeSeconds != nil,
                                dt: dt,
                                handStart: Layout.rightHandStart,
                                wristBodyStart: Layout.rightWristBodyStart,
                                wristVelocityStart: Layout.rightWristVelocityStart,
                                into: &values)
        next.previousRightNormalized = right.normalized
        next.previousRightWristRaw = right.wristRaw
        values[Layout.rightValidIndex] = right.valid ? 1 : 0

        let vector = FeatureVector(values: values,
                                   timeSeconds: observation.timeSeconds,
                                   seq: observation.seq,
                                   leftHandValid: left.valid,
                                   rightHandValid: right.valid)
        return (vector, next)
    }

    // MARK: - Per-hand

    private static func processHand(_ chirality: Chirality,
                                    observation: PoseObservation,
                                    previousNormalized: [SIMD2<Float>]?,
                                    previousWristRaw: SIMD2<Float>?,
                                    hadPreviousTime: Bool,
                                    dt: Float,
                                    handStart: Int,
                                    wristBodyStart: Int,
                                    wristVelocityStart: Int,
                                    into values: inout [Float])
        -> (valid: Bool, normalized: [SIMD2<Float>]?, wristRaw: SIMD2<Float>?) {

        guard let hand = resolvedHand(chirality, in: observation),
              let normalized = PoseNormalizer.normalize(points: hand.points,
                                                        confidences: hand.confidences) else {
            // Missing/degenerate hand: features stay zero and velocity state resets so motion
            // doesn't spike when the hand re-enters the frame.
            return (false, nil, nil)
        }

        // Handshape positions.
        for (i, p) in normalized.enumerated() {
            values[handStart + i * 2] = p.x
            values[handStart + i * 2 + 1] = p.y
        }

        // Handshape motion (velocity of normalized joints).
        if let previous = previousNormalized, hadPreviousTime {
            let velocityStart = handStart + Layout.positionsPerHand
            for i in 0..<HandJoint.count {
                let v = (normalized[i] - previous[i]) / dt
                values[velocityStart + i * 2] = v.x
                values[velocityStart + i * 2 + 1] = v.y
            }
        }

        // Signing-space location: raw wrist relative to the body frame.
        let wristRaw = hand.points[HandJoint.wrist.rawValue]
        if let body = observation.body,
           let mid = body.shoulderMidpoint,
           let width = body.shoulderWidth, width > 1e-4 {
            let relative = (wristRaw - mid) / width
            values[wristBodyStart] = relative.x
            values[wristBodyStart + 1] = relative.y
        }

        // Movement path: raw wrist velocity (image-normalized units / second).
        if let previousWrist = previousWristRaw, hadPreviousTime {
            let v = (wristRaw - previousWrist) / dt
            values[wristVelocityStart] = v.x
            values[wristVelocityStart + 1] = v.y
        }

        return (true, normalized, wristRaw)
    }

    /// Picks the hand for a chirality slot. A single hand of unknown chirality is slotted right
    /// (statistically dominant); ambiguity resolves toward the more confident wrist.
    private static func resolvedHand(_ chirality: Chirality, in observation: PoseObservation) -> HandPose? {
        if let exact = observation.hand(chirality) { return exact }
        if chirality == .right,
           observation.hands.count == 1,
           let only = observation.hands.first,
           only.chirality == .unknown {
            return only
        }
        return nil
    }
}
