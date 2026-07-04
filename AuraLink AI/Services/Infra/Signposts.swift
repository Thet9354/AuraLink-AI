//
//  Signposts.swift
//  AuraLink AI
//
//  Centralized OSSignposter instances for latency measurement in Instruments. Every hard PERF
//  gate in docs/PERF.md is measured against one of these categories. Subsystem is shared with
//  the wider "thetpine" portfolio tooling for consistency.
//

import OSLog

nonisolated enum Signposts {
    static let subsystem = "com.thetpine.auralink"

    /// Glass-to-caption and stage latencies (capture→pose, pose→caption, sound→haptic).
    static let latency = OSSignposter(subsystem: subsystem, category: "latency")

    /// Pipeline lifecycle and per-stage intervals (inference, segmentation).
    static let pipeline = OSSignposter(subsystem: subsystem, category: "pipeline")

    /// Governor tier transitions (thermal/battery/memory de-rating).
    static let governor = OSSignposter(subsystem: subsystem, category: "governor")
}
