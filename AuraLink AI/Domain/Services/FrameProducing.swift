//
//  FrameProducing.swift
//  AuraLink AI
//
//  The seam between the camera capture layer and the vision front-end. The Phase 2 `VisionActor`
//  will depend on this protocol, not on `CaptureActor` directly, so capture can be mocked in tests.
//

import Foundation

/// A source of camera frames, delivered through a latest-value stream (buffering policy
/// `.bufferingNewest(1)` — the hardware-boundary form of the `LatestSlot` back-pressure contract:
/// keep the freshest frame, drop stale ones).
nonisolated protocol FrameProducing: Sendable {
    /// Single-consumer stream of camera frames. Stale frames are dropped, not queued.
    var frames: AsyncStream<FrameToken> { get }

    /// Begin capture. Requests camera authorization if needed; throws if unavailable. Idempotent.
    func start() async throws

    /// Stop capture. Idempotent.
    func stop() async
}
