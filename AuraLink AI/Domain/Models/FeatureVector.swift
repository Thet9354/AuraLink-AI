//
//  FeatureVector.swift
//  AuraLink AI
//
//  The per-frame feature representation consumed by segmentation (Phase 3) and DTW matching.
//  Fixed dimension, fixed layout — documented in `FeatureExtractor.Layout` and asserted in tests,
//  because exemplar files recorded during enrollment must remain layout-compatible.
//

nonisolated struct FeatureVector: Sendable {
    /// Feature values in the fixed `FeatureExtractor.Layout` order.
    var values: [Float]
    /// Capture presentation time, in seconds on the capture clock.
    var timeSeconds: Double
    /// Capture sequence number of the source frame.
    var seq: UInt64
    /// Whether each hand contributed real (non-zero-filled) features this frame.
    var leftHandValid: Bool
    var rightHandValid: Bool

    /// True when no hand contributed features — segmentation treats runs of these as rest.
    var isRest: Bool { !leftHandValid && !rightHandValid }
}
