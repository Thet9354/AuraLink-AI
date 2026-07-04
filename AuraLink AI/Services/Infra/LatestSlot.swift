//
//  LatestSlot.swift
//  AuraLink AI
//
//  The load-bearing concurrency primitive.
//
//  A single-slot, latest-value channel that provides implicit back-pressure with a
//  bounded-latency guarantee. Producers NEVER block: `put` overwrites any value that a
//  consumer has not yet taken, intentionally DROPPING the stale one. A single consumer
//  `take`s the freshest value, suspending (without blocking a thread) when the slot is empty.
//
//  Why this exists: a 60 fps camera produces frames faster than any inference stage can
//  consume them. Queueing them is how real-time systems die — latency grows without bound
//  and memory blows up. Dropping to the freshest value caps staleness at one production
//  interval, which is the core real-time invariant of the whole pipeline.
//

import Foundation

/// Single-producer / single-consumer latest-value channel.
///
/// - Producer side: `put(_:)` is O(1) and never suspends; overwrites an un-taken value.
/// - Consumer side: `take()` returns the freshest value, or parks one consumer until a value arrives.
actor LatestSlot<Element: Sendable> {

    private var stored: Element?
    private var waiter: CheckedContinuation<Element, Never>?

    init() {}

    /// Store the newest value. If a consumer is currently parked, hand the value directly to it;
    /// otherwise overwrite the slot (the previously stored value is dropped — this is the
    /// back-pressure mechanism, not a bug).
    func put(_ value: Element) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else {
            stored = value
        }
    }

    /// Take the freshest stored value, or suspend until one is produced.
    ///
    /// Single-consumer by contract: parking a second consumer while one is already parked is a
    /// programming error (asserted in debug). The awaiting task is suspended cooperatively — the
    /// underlying thread (including the main thread, if the caller is `@MainActor`) is not blocked.
    func take() async -> Element {
        if let value = stored {
            stored = nil
            return value
        }
        return await withCheckedContinuation { continuation in
            assert(waiter == nil, "LatestSlot supports a single consumer at a time")
            waiter = continuation
        }
    }

    /// Whether the slot currently holds an un-taken value. Primarily for tests and diagnostics.
    var isEmpty: Bool { stored == nil }

    // NOTE (Phase 1): add cancellation support via `withTaskCancellationHandler` so a cancelled
    // consumer resumes and clears `waiter`. Not required for the Phase 0 mock loop, which never
    // cancels mid-`take`.
}
