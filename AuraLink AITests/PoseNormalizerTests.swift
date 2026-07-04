//
//  PoseNormalizerTests.swift
//  AuraLink AITests
//
//  Phase 2 gate: the same physical handshape must normalize to (near-)identical coordinates
//  regardless of where the signer stands, how far they are from the camera, and camera roll.
//  This invariance is what makes few-shot DTW template matching viable.
//

import Testing
import simd
@testable import AuraLink_AI

struct PoseNormalizerTests {

    /// A synthetic but plausible open hand: wrist at bottom, fingers fanning upward.
    static func syntheticHand() -> [SIMD2<Float>] {
        var points = [SIMD2<Float>](repeating: .zero, count: HandJoint.count)
        points[HandJoint.wrist.rawValue] = SIMD2(0.50, 0.30)
        // Thumb chain, angled left
        points[HandJoint.thumbCMC.rawValue] = SIMD2(0.455, 0.335)
        points[HandJoint.thumbMP.rawValue] = SIMD2(0.425, 0.365)
        points[HandJoint.thumbIP.rawValue] = SIMD2(0.405, 0.395)
        points[HandJoint.thumbTip.rawValue] = SIMD2(0.395, 0.425)
        // Index
        points[HandJoint.indexMCP.rawValue] = SIMD2(0.465, 0.42)
        points[HandJoint.indexPIP.rawValue] = SIMD2(0.46, 0.47)
        points[HandJoint.indexDIP.rawValue] = SIMD2(0.4575, 0.505)
        points[HandJoint.indexTip.rawValue] = SIMD2(0.455, 0.535)
        // Middle
        points[HandJoint.middleMCP.rawValue] = SIMD2(0.50, 0.43)
        points[HandJoint.middlePIP.rawValue] = SIMD2(0.50, 0.485)
        points[HandJoint.middleDIP.rawValue] = SIMD2(0.50, 0.525)
        points[HandJoint.middleTip.rawValue] = SIMD2(0.50, 0.56)
        // Ring
        points[HandJoint.ringMCP.rawValue] = SIMD2(0.535, 0.42)
        points[HandJoint.ringPIP.rawValue] = SIMD2(0.54, 0.47)
        points[HandJoint.ringDIP.rawValue] = SIMD2(0.5425, 0.505)
        points[HandJoint.ringTip.rawValue] = SIMD2(0.545, 0.535)
        // Little
        points[HandJoint.littleMCP.rawValue] = SIMD2(0.565, 0.40)
        points[HandJoint.littlePIP.rawValue] = SIMD2(0.575, 0.44)
        points[HandJoint.littleDIP.rawValue] = SIMD2(0.58, 0.465)
        points[HandJoint.littleTip.rawValue] = SIMD2(0.585, 0.49)
        return points
    }

    static func fullConfidence() -> [Float] {
        [Float](repeating: 0.9, count: HandJoint.count)
    }

    /// Applies a similarity transform p' = s·R(θ)·p + t to every point.
    static func transformed(_ points: [SIMD2<Float>],
                            scale s: Float, rotation theta: Float, translation t: SIMD2<Float>) -> [SIMD2<Float>] {
        let c = cosf(theta)
        let sn = sinf(theta)
        return points.map { p in
            let rotated = SIMD2<Float>(p.x * c - p.y * sn, p.x * sn + p.y * c)
            return rotated * s + t
        }
    }

    private func maxDeviation(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>]) -> Float {
        zip(a, b).map { simd_length($0 - $1) }.max() ?? .infinity
    }

    // MARK: - Invariance (the core property)

    @Test func invariantUnderTranslation() throws {
        let base = Self.syntheticHand()
        let conf = Self.fullConfidence()
        let moved = Self.transformed(base, scale: 1, rotation: 0, translation: SIMD2(0.31, -0.12))

        let n1 = try #require(PoseNormalizer.normalize(points: base, confidences: conf))
        let n2 = try #require(PoseNormalizer.normalize(points: moved, confidences: conf))
        #expect(maxDeviation(n1, n2) < 1e-4)
    }

    @Test func invariantUnderScale() throws {
        let base = Self.syntheticHand()
        let conf = Self.fullConfidence()
        let scaled = Self.transformed(base, scale: 2.4, rotation: 0, translation: .zero)

        let n1 = try #require(PoseNormalizer.normalize(points: base, confidences: conf))
        let n2 = try #require(PoseNormalizer.normalize(points: scaled, confidences: conf))
        #expect(maxDeviation(n1, n2) < 1e-4)
    }

    @Test func invariantUnderRotation() throws {
        let base = Self.syntheticHand()
        let conf = Self.fullConfidence()
        let rotated = Self.transformed(base, scale: 1, rotation: 0.8, translation: .zero)

        let n1 = try #require(PoseNormalizer.normalize(points: base, confidences: conf))
        let n2 = try #require(PoseNormalizer.normalize(points: rotated, confidences: conf))
        #expect(maxDeviation(n1, n2) < 1e-3)
    }

    @Test func invariantUnderCombinedSimilarityTransform() throws {
        let base = Self.syntheticHand()
        let conf = Self.fullConfidence()
        let moved = Self.transformed(base, scale: 0.55, rotation: -1.2, translation: SIMD2(-0.2, 0.4))

        let n1 = try #require(PoseNormalizer.normalize(points: base, confidences: conf))
        let n2 = try #require(PoseNormalizer.normalize(points: moved, confidences: conf))
        #expect(maxDeviation(n1, n2) < 1e-3)
    }

    // MARK: - Canonical frame

    @Test func wristLandsAtOriginAndPalmAxisIsUnitY() throws {
        let normalized = try #require(PoseNormalizer.normalize(points: Self.syntheticHand(),
                                                               confidences: Self.fullConfidence()))
        let wrist = normalized[HandJoint.wrist.rawValue]
        #expect(simd_length(wrist) < 1e-5)

        let middle = normalized[HandJoint.middleMCP.rawValue]
        #expect(abs(middle.x) < 1e-5)
        #expect(abs(middle.y - 1) < 1e-5)
    }

    // MARK: - Honest failure

    @Test func missingWristFailsNormalization() {
        var conf = Self.fullConfidence()
        conf[HandJoint.wrist.rawValue] = 0.1
        let result = PoseNormalizer.normalize(points: Self.syntheticHand(), confidences: conf)
        #expect(result == nil)
    }

    @Test func degeneratePalmFailsNormalization() {
        let collapsed = [SIMD2<Float>](repeating: SIMD2(0.5, 0.5), count: HandJoint.count)
        let result = PoseNormalizer.normalize(points: collapsed, confidences: Self.fullConfidence())
        #expect(result == nil)
    }

    @Test func lowConfidenceJointsAreZeroed() throws {
        var conf = Self.fullConfidence()
        conf[HandJoint.littleTip.rawValue] = 0.05
        let normalized = try #require(PoseNormalizer.normalize(points: Self.syntheticHand(),
                                                               confidences: conf))
        #expect(normalized[HandJoint.littleTip.rawValue] == .zero)
    }
}
