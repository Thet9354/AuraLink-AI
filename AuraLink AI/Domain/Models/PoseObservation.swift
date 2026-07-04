//
//  PoseObservation.swift
//  AuraLink AI
//
//  Framework-free pose value types. `VisionActor` maps VNHumanHandPoseObservation /
//  VNHumanBodyPoseObservation into these `Sendable` snapshots, so downstream stages (feature
//  extraction, segmentation, DTW) never touch Vision types — and can be tested with synthetic data.
//
//  Coordinate convention: image-normalized [0,1] with the origin at the BOTTOM-LEFT (Vision's
//  convention). The UI layer flips the y-axis when drawing.
//

import simd

/// The 21 hand joints, in fixed order. Raw values index directly into `HandPose` arrays.
nonisolated enum HandJoint: Int, Sendable, CaseIterable {
    case wrist = 0
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    static let count = 21
}

nonisolated enum Chirality: Sendable {
    case left, right, unknown
}

/// One detected hand: 21 joint positions with per-joint confidence.
nonisolated struct HandPose: Sendable {
    /// Joint positions, indexed by `HandJoint.rawValue`. Image-normalized, bottom-left origin.
    var points: [SIMD2<Float>]
    /// Per-joint confidence in [0,1]; a joint below the pipeline threshold is treated as missing.
    var confidences: [Float]
    var chirality: Chirality

    init(points: [SIMD2<Float>], confidences: [Float], chirality: Chirality) {
        precondition(points.count == HandJoint.count && confidences.count == HandJoint.count)
        self.points = points
        self.confidences = confidences
        self.chirality = chirality
    }
}

/// Sparse body anchors used to place hands in signing space (ASL signs are located relative to
/// the body: chin, chest, shoulder…). Only what feature extraction needs — not a full skeleton.
nonisolated struct BodyAnchors: Sendable {
    var nose: SIMD2<Float>?
    var leftShoulder: SIMD2<Float>?
    var rightShoulder: SIMD2<Float>?

    /// Midpoint between the shoulders, if both are present.
    var shoulderMidpoint: SIMD2<Float>? {
        guard let l = leftShoulder, let r = rightShoulder else { return nil }
        return (l + r) * 0.5
    }

    /// Shoulder-to-shoulder distance — the body-scale unit for signing-space coordinates.
    var shoulderWidth: Float? {
        guard let l = leftShoulder, let r = rightShoulder else { return nil }
        return simd_length(r - l)
    }
}

/// A complete per-frame pose snapshot.
nonisolated struct PoseObservation: Sendable {
    /// 0–2 detected hands.
    var hands: [HandPose]
    /// Body anchors; may be carried over from a recent frame (body pose is duty-cycled).
    var body: BodyAnchors?
    /// Capture presentation time, in seconds on the capture clock.
    var timeSeconds: Double
    /// Capture sequence number of the source frame.
    var seq: UInt64

    /// The hand of a given chirality with the most confident wrist, if any.
    func hand(_ chirality: Chirality) -> HandPose? {
        hands.filter { $0.chirality == chirality }
             .max { $0.confidences[HandJoint.wrist.rawValue] < $1.confidences[HandJoint.wrist.rawValue] }
    }
}
