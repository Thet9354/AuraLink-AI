//
//  FeatureFactory.swift
//  AuraLink AITests
//
//  Synthetic feature builders shared across Phase 3 tests. Produces full-layout (178-dim)
//  feature vectors so segmenter/DTW/matcher code exercises real indices.
//

import Foundation
import simd
@testable import AuraLink_AI

enum FeatureFactory {

    typealias Layout = FeatureExtractor.Layout

    /// A feature vector with a right hand present, a distinct handshape "signature" per `seed`,
    /// a chosen wrist speed (drives motion energy), and a raw wrist position (drives segmentation).
    static func frame(seed: Float,
                      wristSpeed: Float,
                      time: Double,
                      seq: UInt64,
                      rightValid: Bool = true,
                      wrist: SIMD2<Float> = SIMD2(0.5, 0.5)) -> FeatureVector {
        var v = [Float](repeating: 0, count: Layout.dimension)
        if rightValid {
            v[Layout.rightValidIndex] = 1
            // Handshape positions: a smooth deterministic pattern unique to the seed.
            for i in 0..<Layout.positionsPerHand {
                v[Layout.rightHandStart + i] = sinf(seed + Float(i) * 0.11)
            }
            // Wrist velocity along +x gives the requested speed (drives motion energy).
            v[Layout.rightWristVelocityStart] = wristSpeed
        }
        return FeatureVector(values: v,
                             timeSeconds: time,
                             seq: seq,
                             leftHandValid: false,
                             rightHandValid: rightValid,
                             primaryWrist: rightValid ? wrist : nil)
    }

    /// A resting frame: hand present but motionless (below the close threshold).
    static func rest(seed: Float, time: Double, seq: UInt64) -> FeatureVector {
        frame(seed: seed, wristSpeed: 0, time: time, seq: seq)
    }

    /// An empty frame: no hands (true rest).
    static func empty(time: Double, seq: UInt64) -> FeatureVector {
        FeatureVector(values: [Float](repeating: 0, count: Layout.dimension),
                      timeSeconds: time, seq: seq,
                      leftHandValid: false, rightHandValid: false)
    }

    /// A full-layout exemplar frame array for a sign of a given seed and length.
    static func exemplarFrames(seed: Float, count: Int, wristSpeed: Float = 0.2) -> [[Float]] {
        (0..<count).map { i in
            frame(seed: seed, wristSpeed: wristSpeed, time: Double(i) / 30.0, seq: UInt64(i)).values
        }
    }

    /// A gesture segment for a sign of a given seed and length.
    static func segment(seed: Float, count: Int, wristSpeed: Float = 0.2) -> GestureSegment {
        let frames = (0..<count).map { i in
            frame(seed: seed, wristSpeed: wristSpeed, time: Double(i) / 30.0, seq: UInt64(i))
        }
        return GestureSegment(frames: frames,
                              startSeconds: frames.first?.timeSeconds ?? 0,
                              endSeconds: frames.last?.timeSeconds ?? 0,
                              closedReason: .pause)
    }
}
