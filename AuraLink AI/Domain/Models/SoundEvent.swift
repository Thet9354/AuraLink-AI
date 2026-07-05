//
//  SoundEvent.swift
//  AuraLink AI
//
//  A detected environmental sound, mapped from Apple's on-device SoundAnalysis taxonomy into a
//  curated, urgency-ranked set the app surfaces (arrows + haptics + captions). Only alerting /
//  relevant classes pass through; the long tail is ignored so the user isn't spammed.
//
//  `azimuth` and `depth` are present in the model but nil in v1: direction (multi-mic beamforming)
//  and distance (LiDAR on Pro) are deferred — see docs/ROADMAP.md.
//

import Foundation

nonisolated enum SoundUrgency: Int, Sendable, Comparable {
    case info = 0
    case warn = 1
    case alert = 2
    static func < (lhs: SoundUrgency, rhs: SoundUrgency) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum SoundCategory: String, Sendable {
    case alarm, siren, vehicleHorn, doorbell, knock, phone, babyCry, shout
    case glassBreak, dogBark, speech, applause, water, footsteps, other
}

nonisolated struct SoundEvent: Sendable, Identifiable {
    let id: UUID
    var category: SoundCategory
    var displayName: String
    var confidence: Float
    var urgency: SoundUrgency
    var azimuth: Float?     // radians, clockwise from forward — deferred (nil) in v1
    var depth: Float?       // meters — deferred (nil) in v1
    var timeSeconds: Double

    init(id: UUID = UUID(),
         category: SoundCategory,
         displayName: String,
         confidence: Float,
         urgency: SoundUrgency,
         azimuth: Float? = nil,
         depth: Float? = nil,
         timeSeconds: Double) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.confidence = confidence
        self.urgency = urgency
        self.azimuth = azimuth
        self.depth = depth
        self.timeSeconds = timeSeconds
    }
}

/// Maps a SoundAnalysis classifier identifier to a curated `SoundEvent`. Returns nil for
/// irrelevant classes or low confidence. Keyword-based so it is robust to minor taxonomy naming.
nonisolated enum SoundEventMapper {

    /// Minimum classifier confidence to surface an event. Alerting sounds get a lower bar.
    static let baseConfidence: Float = 0.55
    static let alertConfidence: Float = 0.40

    private struct Rule {
        let keywords: [String]
        let category: SoundCategory
        let displayName: String
        let urgency: SoundUrgency
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["smoke_detector", "smoke_alarm", "fire_alarm", "alarm_clock", "alarm", "siren"],
             category: .alarm, displayName: "Alarm", urgency: .alert),
        Rule(keywords: ["civil_defense_siren", "emergency_vehicle", "police", "ambulance", "fire_engine"],
             category: .siren, displayName: "Siren", urgency: .alert),
        Rule(keywords: ["glass", "shatter"],
             category: .glassBreak, displayName: "Glass breaking", urgency: .alert),
        Rule(keywords: ["shout", "yell", "screaming", "scream"],
             category: .shout, displayName: "Shouting", urgency: .warn),
        Rule(keywords: ["vehicle_horn", "car_horn", "honk", "toot"],
             category: .vehicleHorn, displayName: "Vehicle horn", urgency: .warn),
        Rule(keywords: ["baby_cry", "baby_crying", "infant_cry"],
             category: .babyCry, displayName: "Baby crying", urgency: .warn),
        Rule(keywords: ["doorbell", "ding_dong"],
             category: .doorbell, displayName: "Doorbell", urgency: .warn),
        Rule(keywords: ["knock"],
             category: .knock, displayName: "Knocking", urgency: .warn),
        Rule(keywords: ["telephone", "ringtone", "phone_ring", "cellphone_buzz"],
             category: .phone, displayName: "Phone ringing", urgency: .warn),
        Rule(keywords: ["dog", "bark"],
             category: .dogBark, displayName: "Dog barking", urgency: .info),
        Rule(keywords: ["speech", "conversation", "narration"],
             category: .speech, displayName: "Speech", urgency: .info),
        Rule(keywords: ["applause", "clapping"],
             category: .applause, displayName: "Applause", urgency: .info),
        Rule(keywords: ["water", "faucet", "running_tap"],
             category: .water, displayName: "Water running", urgency: .info),
        Rule(keywords: ["footsteps", "walk"],
             category: .footsteps, displayName: "Footsteps", urgency: .info)
    ]

    static func event(identifier: String, confidence: Float, timeSeconds: Double) -> SoundEvent? {
        let id = identifier.lowercased()
        guard let rule = rules.first(where: { rule in rule.keywords.contains { id.contains($0) } }) else {
            return nil
        }
        let bar = rule.urgency == .alert ? alertConfidence : baseConfidence
        guard confidence >= bar else { return nil }
        return SoundEvent(category: rule.category,
                          displayName: rule.displayName,
                          confidence: confidence,
                          urgency: rule.urgency,
                          timeSeconds: timeSeconds)
    }
}
