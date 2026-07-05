//
//  ExemplarReplayTests.swift
//  AuraLink AITests
//
//  The recorded skeleton is reconstructable from an exemplar's feature frames (sign recall).
//

import simd
import Testing
@testable import AuraLink_AI

struct ExemplarReplayTests {

    private typealias Layout = FeatureExtractor.Layout

    @Test func reconstructsRightHandFramesFromExemplar() {
        let exemplar = SignExemplar(lexID: "hello", frames: FeatureFactory.exemplarFrames(seed: 1.0, count: 10))
        let replay = ExemplarReplay.frames(from: exemplar)

        #expect(replay.count == 10)
        let first = replay.first
        #expect(first?.rightHand?.count == HandJoint.count)   // 21 joints
        #expect(first?.leftHand == nil)                        // single-hand factory → no left

        // The wrist joint round-trips from the stored feature values.
        let storedWristX = exemplar.frames[0][Layout.rightHandStart + HandJoint.wrist.rawValue * 2]
        #expect(first?.rightHand?[HandJoint.wrist.rawValue].x == storedWristX)
    }

    @Test func boundsCoverAllJoints() {
        let exemplar = SignExemplar(lexID: "hello", frames: FeatureFactory.exemplarFrames(seed: 2.0, count: 6))
        let replay = ExemplarReplay.frames(from: exemplar)
        let bounds = ExemplarReplay.bounds(replay)
        #expect(bounds != nil)
        if let bounds {
            #expect(bounds.max.x >= bounds.min.x)
            #expect(bounds.max.y >= bounds.min.y)
        }
    }

    @Test func emptyExemplarYieldsNoBounds() {
        #expect(ExemplarReplay.bounds([]) == nil)
    }
}
