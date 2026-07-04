//
//  PoseNormalizer.swift
//  AuraLink AI
//
//  Canonicalizes a hand pose so recognition is invariant to where the signer stands, how far they
//  are from the camera, and camera roll:
//
//    1. TRANSLATE — wrist to the origin.
//    2. ROTATE   — the wrist→middleMCP axis (the palm axis) to +Y.
//    3. SCALE    — divide by palm length, so the palm axis has unit length.
//
//  The same physical handshape then produces (near-)identical normalized coordinates regardless of
//  position, distance, or roll — which is what makes few-shot DTW template matching viable.
//  Pure function; the invariance property is unit-tested directly.
//

import simd

nonisolated enum PoseNormalizer {

    /// Joints below this confidence are treated as missing and zeroed in the output.
    static let defaultMinConfidence: Float = 0.3

    /// Palm lengths below this (in image-normalized units) are degenerate — the hand is too
    /// small/collapsed to normalize meaningfully.
    static let minPalmLength: Float = 1e-4

    /// Returns the canonicalized 21-joint array, or `nil` if the pose cannot be normalized
    /// (wrist or middleMCP missing, or a degenerate palm). Missing joints come back as `.zero`.
    static func normalize(points: [SIMD2<Float>],
                          confidences: [Float],
                          minConfidence: Float = defaultMinConfidence) -> [SIMD2<Float>]? {
        precondition(points.count == HandJoint.count && confidences.count == HandJoint.count)

        let wristIdx = HandJoint.wrist.rawValue
        let middleIdx = HandJoint.middleMCP.rawValue
        guard confidences[wristIdx] >= minConfidence,
              confidences[middleIdx] >= minConfidence else { return nil }

        let wrist = points[wristIdx]
        let palm = points[middleIdx] - wrist
        let palmLength = simd_length(palm)
        guard palmLength >= minPalmLength else { return nil }

        // Rotation that carries the palm axis onto +Y: rotate by α = atan2(palm.x, palm.y).
        let alpha = atan2f(palm.x, palm.y)
        let cosA = cosf(alpha)
        let sinA = sinf(alpha)

        return (0..<HandJoint.count).map { i in
            guard confidences[i] >= minConfidence else { return .zero }
            let p = points[i] - wrist
            let rotated = SIMD2<Float>(p.x * cosA - p.y * sinA,
                                       p.x * sinA + p.y * cosA)
            return rotated / palmLength
        }
    }
}
