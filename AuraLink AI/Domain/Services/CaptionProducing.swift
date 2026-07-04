//
//  CaptionProducing.swift
//  AuraLink AI
//
//  The seam between the translation pipeline and the UI. The view model depends only on this
//  protocol, never on a concrete pipeline — so the Phase 0 `MockCaptionPipeline` can be swapped
//  for the real capture→vision→fusion→inference graph without touching the UI layer.
//

import Foundation

/// A source of frozen caption values, delivered through a latest-value back-pressure slot.
nonisolated protocol CaptionProducing: Sendable {
    /// The slot the UI consumer drains. Producers overwrite it; the consumer always reads the
    /// freshest caption. Exposed as `nonisolated` state so the consumer needs no actor hop to
    /// obtain the reference.
    var output: LatestSlot<CaptionDTO> { get }

    /// Begin producing captions. Idempotent.
    func start() async

    /// Stop producing and release resources. Idempotent.
    func stop() async
}
