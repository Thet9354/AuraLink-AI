//
//  CaptureCounters.swift
//  AuraLink AI
//
//  Lock-free capture metrics shared between the (nonisolated) video delegate — which increments
//  from the capture queue — and any reader on another isolation domain. Backed by `Atomic`, so it
//  is genuinely `Sendable` (no `@unchecked` needed).
//

import Synchronization

/// A point-in-time snapshot of capture counters.
nonisolated struct CaptureCounts: Sendable {
    var delivered: Int
    var dropped: Int
}

nonisolated final class CaptureCounters: Sendable {
    private let delivered = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    func recordDelivered() {
        delivered.wrappingAdd(1, ordering: .relaxed)
    }

    func recordDropped() {
        dropped.wrappingAdd(1, ordering: .relaxed)
    }

    func snapshot() -> CaptureCounts {
        CaptureCounts(delivered: delivered.load(ordering: .relaxed),
                      dropped: dropped.load(ordering: .relaxed))
    }
}
