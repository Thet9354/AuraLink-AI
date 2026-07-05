//
//  DTWTests.swift
//  AuraLink AITests
//
//  Phase 3 gate: DTW must be zero for identical sequences, invariant to signing-SPEED (time
//  warping), monotonic in dissimilarity, and structurally penalize hand-validity mismatch.
//

import Testing
@testable import AuraLink_AI

struct DTWTests {

    private func makeFrame(_ base: Float, left: Bool = false, right: Bool = true) -> DTWFrame {
        DTWFrame(values: (0..<SignFeatureSlice.dimension).map { base + Float($0) * 0.01 },
                 leftValid: left, rightValid: right)
    }

    private func sequence(_ base: Float, count: Int) -> [DTWFrame] {
        (0..<count).map { makeFrame(base + Float($0) * 0.05) }
    }

    @Test func identicalSequencesHaveZeroDistance() {
        let a = sequence(0.2, count: 12)
        #expect(DTW.distance(a, a) < 1e-5)
    }

    @Test func invariantToTimeWarp() {
        // Same gesture performed at 2× duration: every frame duplicated. DTW should align it back
        // to (near-)zero cost — this is the property that lets one exemplar match varied tempos.
        let normal = sequence(0.2, count: 12)
        let slow = normal.flatMap { [$0, $0] }
        #expect(DTW.distance(normal, slow) < 1e-4)
    }

    @Test func distanceGrowsWithDissimilarity() {
        let base = sequence(0.2, count: 12)
        let near = sequence(0.25, count: 12)   // slightly shifted
        let far = sequence(1.5, count: 12)     // very different

        let dNear = DTW.distance(base, near)
        let dFar = DTW.distance(base, far)
        #expect(dNear > 0)
        #expect(dFar > dNear)
    }

    @Test func validityMismatchAddsPenalty() {
        let a = makeFrame(0.2, left: false, right: true)
        let bSame = makeFrame(0.2, left: false, right: true)
        let bMismatch = makeFrame(0.2, left: true, right: false)   // both hands differ

        #expect(DTW.frameDistance(a, bSame) < 1e-5)
        // Two mismatched validity flags → ~2 × validityPenalty.
        #expect(DTW.frameDistance(a, bMismatch) >= DTW.validityPenalty)
    }

    @Test func emptySequenceIsInfinite() {
        #expect(DTW.distance([], sequence(0.2, count: 5)) == .infinity)
    }

    @Test func meanFrameAveragesValues() {
        let frames = [makeFrame(0.0), makeFrame(1.0)]
        let mean = DTW.meanFrame(frames)
        // Element 0: (0.0 + 1.0)/2 = 0.5.
        #expect(abs(mean.values[0] - 0.5) < 1e-5)
        #expect(mean.rightValid)      // both frames right-valid → majority right-valid
        #expect(!mean.leftValid)
    }

    @Test func longSequencesStayFiniteViaDownsampling() {
        // Beyond DTW.maxFrames, sequences are stride-downsampled; distance must remain finite.
        let a = sequence(0.2, count: 200)
        let b = sequence(0.2, count: 200)
        let d = DTW.distance(a, b)
        #expect(d.isFinite)
        #expect(d < 1e-4)
    }
}
