//
//  DTW.swift
//  AuraLink AI
//
//  Dynamic time warping over feature-frame sequences — the core of few-shot sign matching.
//  DTW absorbs signing-SPEED variation for free (the same sign performed slower/faster aligns
//  along the warping path), needs only a handful of exemplars per sign, and yields a *distance*
//  that calibrates into honest confidence. A Sakoe-Chiba band bounds the warp (a sign performed
//  3× off-tempo should NOT match) and keeps cost at O(n·band).
//
//  Frames are pre-sliced to the match-relevant sub-vector (`DTWFrame`) so the inner loop touches
//  ~92 floats, not the full 178-dim layout.
//

import Foundation

/// A frame reduced to the match-relevant features, with per-hand validity for mismatch penalties.
nonisolated struct DTWFrame: Sendable {
    /// Weighted feature slice (see `SignFeatureSlice`).
    var values: [Float]
    var leftValid: Bool
    var rightValid: Bool
}

/// Extracts and weights the match-relevant slice of the 178-dim feature layout.
nonisolated enum SignFeatureSlice {

    /// Block weights: handshape carries most of the signal; signing-space location is a strong
    /// discriminator (few dims, so weighted up); wrist velocity is scaled down because its
    /// magnitude (units/second) dwarfs normalized positions.
    static let shapeWeight: Float = 1.0
    static let bodyWeight: Float = 1.5
    static let wristVelocityWeight: Float = 0.15

    /// 42 + 42 shape positions, 4 signing-space, 4 wrist velocity = 92 values.
    static let dimension = FeatureExtractor.Layout.positionsPerHand * 2 + 4 + 4

    static func slice(_ values: [Float], leftValid: Bool, rightValid: Bool) -> DTWFrame {
        typealias Layout = FeatureExtractor.Layout
        var out = [Float]()
        out.reserveCapacity(dimension)

        for i in 0..<Layout.positionsPerHand {
            out.append(values[Layout.leftHandStart + i] * shapeWeight)
        }
        for i in 0..<Layout.positionsPerHand {
            out.append(values[Layout.rightHandStart + i] * shapeWeight)
        }
        for i in 0..<4 {
            out.append(values[Layout.leftWristBodyStart + i] * bodyWeight)
        }
        for i in 0..<4 {
            out.append(values[Layout.leftWristVelocityStart + i] * wristVelocityWeight)
        }
        return DTWFrame(values: out, leftValid: leftValid, rightValid: rightValid)
    }

    static func slice(_ vector: FeatureVector) -> DTWFrame {
        slice(vector.values, leftValid: vector.leftHandValid, rightValid: vector.rightHandValid)
    }

    /// Slices a stored exemplar frame (validity recovered from the layout's flag indices).
    static func slice(exemplarFrame values: [Float]) -> DTWFrame {
        typealias Layout = FeatureExtractor.Layout
        return slice(values,
                     leftValid: values[Layout.leftValidIndex] > 0.5,
                     rightValid: values[Layout.rightValidIndex] > 0.5)
    }
}

nonisolated enum DTW {

    /// Sakoe-Chiba band: |i − j| ≤ max(minBand, bandFraction · max(n, m)).
    static let bandFraction: Float = 0.2
    static let minBand = 5

    /// One hand present in one frame but not the other is a real structural mismatch.
    static let validityPenalty: Float = 1.0

    /// Sequences longer than this are stride-downsampled before matching — enough temporal
    /// resolution for signs, bounded cost for the DP.
    static let maxFrames = 64

    /// Path-length-normalized DTW distance (per-step cost, comparable across sequence lengths).
    /// Returns `.infinity` if either sequence is empty.
    static func distance(_ a: [DTWFrame], _ b: [DTWFrame]) -> Float {
        let s1 = downsample(a)
        let s2 = downsample(b)
        let n = s1.count
        let m = s2.count
        guard n > 0, m > 0 else { return .infinity }

        let band = max(minBand, Int(bandFraction * Float(max(n, m))))
        // Band follows the ideal warping diagonal (slope m/n), not the i=j line — otherwise a
        // 2× tempo difference could never reach the corner. Deviation from that diagonal, not raw
        // |i−j|, is what a signing-speed change should be bounded by.
        let slope = Double(m) / Double(n)

        var previous = [Float](repeating: .infinity, count: m + 1)
        previous[0] = 0

        for i in 1...n {
            var current = [Float](repeating: .infinity, count: m + 1)
            let center = Int((Double(i) * slope).rounded())
            let lo = max(1, center - band)
            let hi = min(m, center + band)
            if lo <= hi {
                for j in lo...hi {
                    let best = min(previous[j],        // insertion
                                   current[j - 1],     // deletion
                                   previous[j - 1])    // match
                    if best.isFinite {
                        current[j] = frameDistance(s1[i - 1], s2[j - 1]) + best
                    }
                }
            }
            previous = current
        }

        let total = previous[m]
        guard total.isFinite else { return .infinity }
        return total / Float(n + m)
    }

    /// Euclidean distance over the weighted slice, plus a penalty per mismatched hand validity.
    static func frameDistance(_ a: DTWFrame, _ b: DTWFrame) -> Float {
        var sum: Float = 0
        for i in 0..<a.values.count {
            let d = a.values[i] - b.values[i]
            sum += d * d
        }
        var distance = sum.squareRoot()
        if a.leftValid != b.leftValid { distance += validityPenalty }
        if a.rightValid != b.rightValid { distance += validityPenalty }
        return distance
    }

    /// Mean frame of a sequence — the cheap first-stage prune metric in `SignMatcher`.
    static func meanFrame(_ frames: [DTWFrame]) -> DTWFrame {
        guard let first = frames.first else {
            return DTWFrame(values: [], leftValid: false, rightValid: false)
        }
        var mean = [Float](repeating: 0, count: first.values.count)
        var leftCount = 0
        var rightCount = 0
        for frame in frames {
            for i in 0..<mean.count { mean[i] += frame.values[i] }
            if frame.leftValid { leftCount += 1 }
            if frame.rightValid { rightCount += 1 }
        }
        let n = Float(frames.count)
        for i in 0..<mean.count { mean[i] /= n }
        return DTWFrame(values: mean,
                        leftValid: leftCount * 2 > frames.count,
                        rightValid: rightCount * 2 > frames.count)
    }

    private static func downsample(_ frames: [DTWFrame]) -> [DTWFrame] {
        guard frames.count > maxFrames else { return frames }
        let stride = Int((Float(frames.count) / Float(maxFrames)).rounded(.up))
        return Swift.stride(from: 0, to: frames.count, by: stride).map { frames[$0] }
    }
}
