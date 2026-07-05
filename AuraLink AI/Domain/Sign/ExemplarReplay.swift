//
//  ExemplarReplay.swift
//  AuraLink AI
//
//  Reconstructs the animated hand skeleton of a recorded gesture from its stored exemplar. The
//  exemplar's feature frames already contain the normalized joint positions (canonical space:
//  wrist at origin, palm axis up, unit scale), so a user can *watch back* the gesture they assigned
//  to a sign — no extra storage, and it directly answers "which gesture did I use for this?"
//

import simd

/// One frame of a replay: the present hands' 21 normalized joints.
nonisolated struct SkeletonReplayFrame: Sendable {
    var rightHand: [SIMD2<Float>]?
    var leftHand: [SIMD2<Float>]?

    var hands: [[SIMD2<Float>]] { [rightHand, leftHand].compactMap { $0 } }
}

nonisolated enum ExemplarReplay {
    private typealias Layout = FeatureExtractor.Layout

    static func frames(from exemplar: SignExemplar) -> [SkeletonReplayFrame] {
        exemplar.frames.compactMap { values in
            guard values.count == Layout.dimension else { return nil }
            return SkeletonReplayFrame(
                rightHand: hand(values, validIndex: Layout.rightValidIndex, start: Layout.rightHandStart),
                leftHand: hand(values, validIndex: Layout.leftValidIndex, start: Layout.leftHandStart))
        }
    }

    private static func hand(_ values: [Float], validIndex: Int, start: Int) -> [SIMD2<Float>]? {
        guard values[validIndex] > 0.5 else { return nil }
        return (0..<HandJoint.count).map { SIMD2(values[start + $0 * 2], values[start + $0 * 2 + 1]) }
    }

    /// Bounding box over every joint in every frame, so the replay can be scaled to fit without
    /// jumping between frames. Returns nil for an empty replay.
    static func bounds(_ frames: [SkeletonReplayFrame]) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        let all = frames.flatMap { $0.hands.flatMap { $0 } }
        guard let first = all.first else { return nil }
        var lo = first, hi = first
        for p in all {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }
}
