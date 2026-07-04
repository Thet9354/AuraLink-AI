//
//  CapabilityProbe.swift
//  AuraLink AI
//
//  Classifies the current device into a `DeviceRung` at launch.
//
//  Phase 0 uses a conservative model-identifier heuristic. The precise identifier→chip lookup
//  table (and an ANE micro-benchmark fallback for unknown future devices) lands in Phase 5;
//  see docs/ROADMAP.md. Unknown / simulator / iPad cases map to the safe middle rung rather
//  than optimistically to the top.
//

import Foundation

nonisolated enum CapabilityProbe {

    /// Detect the device rung. Never traps; falls back to `.a15` for anything it cannot classify.
    static func detectRung() -> DeviceRung {
        guard let major = iPhoneMajorVersion(from: machineIdentifier()) else {
            return .a15   // simulator, iPad, or an unrecognized identifier → safe middle
        }
        switch major {
        case 17...:      return .a17plus   // iPhone 16 line (A18) and newer
        case 16:         return .a17plus   // iPhone 15 line — includes A17 Pro
        case 14...15:    return .a15       // iPhone 13–14 line (A15/A16)
        default:         return .a14floor  // iPhone 12 (A14) and older
        }
    }

    /// The raw hardware model identifier, e.g. "iPhone16,1". On the simulator, reads the
    /// modeled device from the environment rather than the host Mac's identifier.
    static func machineIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Parses the leading integer of an "iPhoneNN,M" identifier. Returns nil for non-iPhone ids.
    private static func iPhoneMajorVersion(from model: String) -> Int? {
        let prefix = "iPhone"
        guard model.hasPrefix(prefix) else { return nil }
        let digits = model.dropFirst(prefix.count).prefix { $0.isNumber }
        return Int(digits)
    }
}
