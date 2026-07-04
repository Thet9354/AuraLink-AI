//
//  PoseProducing.swift
//  AuraLink AI
//
//  The seam between the vision front-end and its consumers (the pose preview now; the Phase 3
//  `FusionActor` next). Consumers depend on this protocol, not on `VisionActor`, so they can be
//  tested with synthetic pose streams.
//

nonisolated protocol PoseProducing: Sendable {
    /// Latest-value stream of per-frame pose snapshots. Single consumer; stale poses are dropped.
    var poses: LatestSlot<PoseObservation> { get }
}
