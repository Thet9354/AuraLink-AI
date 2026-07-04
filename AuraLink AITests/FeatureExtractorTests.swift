//
//  FeatureExtractorTests.swift
//  AuraLink AITests
//
//  Phase 2 gate: the fixed feature layout, validity flags, velocity semantics, and signing-space
//  coordinates. Layout stability matters — enrollment exemplars are recorded against it.
//

import Testing
import simd
@testable import AuraLink_AI

struct FeatureExtractorTests {

    private typealias Layout = FeatureExtractor.Layout

    private func observation(hands: [HandPose],
                             body: BodyAnchors? = nil,
                             time: Double,
                             seq: UInt64 = 1) -> PoseObservation {
        PoseObservation(hands: hands, body: body, timeSeconds: time, seq: seq)
    }

    private func rightHand(points: [SIMD2<Float>]? = nil) -> HandPose {
        HandPose(points: points ?? PoseNormalizerTests.syntheticHand(),
                 confidences: PoseNormalizerTests.fullConfidence(),
                 chirality: .right)
    }

    @Test func dimensionAndLayoutAreStable() {
        // Freeze the v1 layout: 2×84 hand blocks + 2×2 body-relative + 2×2 wrist velocity + 2 flags.
        #expect(Layout.dimension == 178)
        #expect(Layout.version == 1)
        #expect(Layout.rightHandStart == 84)
        #expect(Layout.leftValidIndex == 176)
        #expect(Layout.rightValidIndex == 177)
    }

    @Test func emptyObservationIsRestWithZeroFeatures() {
        let obs = observation(hands: [], time: 0)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())

        #expect(vector.isRest)
        #expect(!vector.leftHandValid && !vector.rightHandValid)
        #expect(vector.values.allSatisfy { $0 == 0 })
        #expect(vector.values.count == Layout.dimension)
    }

    @Test func rightHandFillsRightBlockOnly() {
        let obs = observation(hands: [rightHand()], time: 0)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())

        #expect(vector.rightHandValid && !vector.leftHandValid)
        #expect(vector.values[Layout.rightValidIndex] == 1)
        #expect(vector.values[Layout.leftValidIndex] == 0)

        let leftBlock = vector.values[Layout.leftHandStart..<Layout.leftHandStart + Layout.perHand]
        #expect(leftBlock.allSatisfy { $0 == 0 })

        let rightPositions = vector.values[Layout.rightHandStart..<Layout.rightHandStart + Layout.positionsPerHand]
        #expect(rightPositions.contains { $0 != 0 })
    }

    @Test func unknownChiralitySingleHandSlotsRight() {
        let hand = HandPose(points: PoseNormalizerTests.syntheticHand(),
                            confidences: PoseNormalizerTests.fullConfidence(),
                            chirality: .unknown)
        let obs = observation(hands: [hand], time: 0)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())
        #expect(vector.rightHandValid)
        #expect(!vector.leftHandValid)
    }

    @Test func translatedHandHasZeroShapeVelocityButNonzeroWristVelocity() {
        // Same handshape, globally translated between frames: normalization removes the motion
        // from the shape block, while the raw wrist velocity captures the movement path.
        let base = PoseNormalizerTests.syntheticHand()
        let moved = PoseNormalizerTests.transformed(base, scale: 1, rotation: 0,
                                                    translation: SIMD2(0.1, 0.05))

        let obs1 = observation(hands: [rightHand(points: base)], time: 0, seq: 1)
        let obs2 = observation(hands: [rightHand(points: moved)], time: 0.1, seq: 2)

        let (_, state1) = FeatureExtractor.extract(from: obs1, state: .init())
        let (vector2, _) = FeatureExtractor.extract(from: obs2, state: state1)

        let shapeVelocity = vector2.values[
            (Layout.rightHandStart + Layout.positionsPerHand)..<(Layout.rightHandStart + Layout.perHand)
        ]
        #expect(shapeVelocity.allSatisfy { abs($0) < 1e-2 })

        let wristVX = vector2.values[Layout.rightWristVelocityStart]
        let wristVY = vector2.values[Layout.rightWristVelocityStart + 1]
        #expect(abs(wristVX - 1.0) < 1e-3)    // 0.1 units / 0.1 s
        #expect(abs(wristVY - 0.5) < 1e-3)    // 0.05 units / 0.1 s
    }

    @Test func firstFrameHasNoVelocity() {
        let obs = observation(hands: [rightHand()], time: 5)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())

        let velocities = vector.values[
            (Layout.rightHandStart + Layout.positionsPerHand)..<(Layout.rightHandStart + Layout.perHand)
        ]
        #expect(velocities.allSatisfy { $0 == 0 })
        #expect(vector.values[Layout.rightWristVelocityStart] == 0)
    }

    @Test func handReappearanceDoesNotSpikeVelocity() {
        // Hand present → absent → present again: velocity state must reset on the gap.
        let obs1 = observation(hands: [rightHand()], time: 0, seq: 1)
        let obs2 = observation(hands: [], time: 0.1, seq: 2)
        let moved = PoseNormalizerTests.transformed(PoseNormalizerTests.syntheticHand(),
                                                    scale: 1, rotation: 0, translation: SIMD2(0.3, 0.3))
        let obs3 = observation(hands: [rightHand(points: moved)], time: 0.2, seq: 3)

        let (_, s1) = FeatureExtractor.extract(from: obs1, state: .init())
        let (_, s2) = FeatureExtractor.extract(from: obs2, state: s1)
        let (vector3, _) = FeatureExtractor.extract(from: obs3, state: s2)

        let velocities = vector3.values[
            (Layout.rightHandStart + Layout.positionsPerHand)..<(Layout.rightHandStart + Layout.perHand)
        ]
        #expect(velocities.allSatisfy { $0 == 0 })
        #expect(vector3.values[Layout.rightWristVelocityStart] == 0)
    }

    @Test func signingSpaceCoordinatesAreBodyRelative() {
        // Shoulders at ±0.1 around x=0.5 (width 0.2), midpoint (0.5, 0.6). The synthetic hand's
        // wrist is (0.5, 0.3) → relative (0, −1.5) in shoulder-width units.
        let body = BodyAnchors(nose: SIMD2(0.5, 0.75),
                               leftShoulder: SIMD2(0.4, 0.6),
                               rightShoulder: SIMD2(0.6, 0.6))
        let obs = observation(hands: [rightHand()], body: body, time: 0)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())

        #expect(abs(vector.values[Layout.rightWristBodyStart] - 0.0) < 1e-4)
        #expect(abs(vector.values[Layout.rightWristBodyStart + 1] - (-1.5)) < 1e-4)
    }

    @Test func missingBodyLeavesSigningSpaceZero() {
        let obs = observation(hands: [rightHand()], body: nil, time: 0)
        let (vector, _) = FeatureExtractor.extract(from: obs, state: .init())
        #expect(vector.values[Layout.rightWristBodyStart] == 0)
        #expect(vector.values[Layout.rightWristBodyStart + 1] == 0)
    }
}
