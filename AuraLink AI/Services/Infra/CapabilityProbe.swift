//
//  CapabilityProbe.swift
//  AuraLink AI
//
//  Classifies the current device into a `DeviceRung` at launch, three ways, in order:
//    1. an exact identifier → rung table for known iPhones (authoritative),
//    2. an iPhone major-version heuristic for newer-than-table devices,
//    3. a RAM-based fallback for anything unrecognized (iPad, simulator, future hardware).
//
//  Classification maps to the *Pro-vs-non-Pro-aware* chip generation — e.g. iPhone 15 Pro (A17
//  Pro, ANE-class) is `.a17plus` while the base iPhone 15 (A16) is `.a15`. A true ANE-latency
//  micro-benchmark would be more precise for unknown future devices; the RAM proxy is the honest,
//  cheap stand-in (RAM tracks chip generation closely) and is flagged as such.
//

import Foundation

nonisolated enum CapabilityProbe {

    /// Detect the device rung. Never traps.
    static func detectRung() -> DeviceRung {
        let model = machineIdentifier()
        if let exact = knownDevices[model] {
            return exact
        }
        if let major = iPhoneMajorVersion(from: model) {
            switch major {
            case 18...: return .a17plus   // newer than the table — assume flagship-class
            case 16...17: return .a17plus // iPhone 15 Pro / 16 line
            case 14...15: return .a15     // iPhone 13/14 line
            default: return .a14floor     // iPhone 12 (A14) and older
            }
        }
        return fallbackByMemory()
    }

    /// Exact identifier → rung for shipped iPhones. Pro models with an ANE-class chip are `.a17plus`.
    private static let knownDevices: [String: DeviceRung] = [
        // A14 / A13 class → floor.
        "iPhone12,1": .a14floor, "iPhone12,3": .a14floor, "iPhone12,5": .a14floor,  // 11 / 11 Pro
        "iPhone12,8": .a14floor,                                                    // SE 2
        "iPhone13,1": .a14floor, "iPhone13,2": .a14floor,                           // 12 mini / 12
        "iPhone13,3": .a14floor, "iPhone13,4": .a14floor,                           // 12 Pro / Pro Max
        // A15 / A16 class → middle.
        "iPhone14,4": .a15, "iPhone14,5": .a15,                                     // 13 mini / 13
        "iPhone14,2": .a15, "iPhone14,3": .a15,                                     // 13 Pro / Pro Max
        "iPhone14,6": .a15,                                                         // SE 3
        "iPhone14,7": .a15, "iPhone14,8": .a15,                                     // 14 / 14 Plus
        "iPhone15,2": .a15, "iPhone15,3": .a15,                                     // 14 Pro / Pro Max (A16)
        "iPhone15,4": .a15, "iPhone15,5": .a15,                                     // 15 / 15 Plus (A16)
        // A17 Pro / A18 class → top.
        "iPhone16,1": .a17plus, "iPhone16,2": .a17plus,                             // 15 Pro / Pro Max (A17 Pro)
        "iPhone17,3": .a17plus, "iPhone17,4": .a17plus,                             // 16 / 16 Plus (A18)
        "iPhone17,1": .a17plus, "iPhone17,2": .a17plus,                             // 16 Pro / Pro Max (A18 Pro)
        "iPhone17,5": .a17plus                                                      // 16e
    ]

    /// RAM-based fallback (GB thresholds track chip generation for unrecognized devices).
    private static func fallbackByMemory() -> DeviceRung {
        let gib = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        switch gib {
        case 7...: return .a17plus   // 8 GB+ → A17 Pro / A18 class
        case 5...: return .a15       // 6 GB → A15/A16 class
        default:   return .a14floor  // ≤ 4 GB → A14 and older
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

    /// Classifies an explicit identifier — exposed for tests and diagnostics.
    static func rung(forIdentifier model: String) -> DeviceRung? {
        knownDevices[model]
    }

    /// Parses the leading integer of an "iPhoneNN,M" identifier. Returns nil for non-iPhone ids.
    private static func iPhoneMajorVersion(from model: String) -> Int? {
        let prefix = "iPhone"
        guard model.hasPrefix(prefix) else { return nil }
        let digits = model.dropFirst(prefix.count).prefix { $0.isNumber }
        return Int(digits)
    }
}
