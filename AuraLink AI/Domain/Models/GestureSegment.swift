//
//  GestureSegment.swift
//  AuraLink AI
//
//  A bounded window of feature frames covering one candidate sign, produced by the motion-energy
//  segmenter and consumed by the DTW matcher.
//

nonisolated struct GestureSegment: Sendable {
    enum ClosedReason: Sendable {
        /// Motion energy fell below the rest threshold for the required dwell (a natural pause).
        case pause
        /// The segment hit the maximum length and was force-closed.
        case maxLength
    }

    /// Feature frames, oldest → newest, trailing rest frames trimmed.
    var frames: [FeatureVector]
    var startSeconds: Double
    var endSeconds: Double
    var closedReason: ClosedReason

    var frameCount: Int { frames.count }
    var durationSeconds: Double { endSeconds - startSeconds }
}
