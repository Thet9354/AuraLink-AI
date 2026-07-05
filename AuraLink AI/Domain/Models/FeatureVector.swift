//
//  FeatureVector.swift
//  AuraLink AI
//
//  The per-frame feature representation consumed by segmentation (Phase 3) and DTW matching.
//  Fixed dimension, fixed layout — documented in `FeatureExtractor.Layout` and asserted in tests,
//  because exemplar files recorded during enrollment must remain layout-compatible.
//

import simd

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
    /// Raw (image-normalized) wrist position of the active hand — a jitter-robust anchor the
    /// segmenter uses to detect a held sign (finger-joint velocity is too noisy for that). `nil`
    /// when no hand is present. Not part of the DTW feature layout.
    var primaryWrist: SIMD2<Float>?

    init(values: [Float],
         timeSeconds: Double,
         seq: UInt64,
         leftHandValid: Bool,
         rightHandValid: Bool,
         primaryWrist: SIMD2<Float>? = nil) {
        self.values = values
        self.timeSeconds = timeSeconds
        self.seq = seq
        self.leftHandValid = leftHandValid
        self.rightHandValid = rightHandValid
        self.primaryWrist = primaryWrist
    }

    /// True when no hand contributed features — segmentation treats runs of these as rest.
    var isRest: Bool { !leftHandValid && !rightHandValid }
}
