//
//  ProsodyAndVADTests.swift
//  AuraLink AITests
//
//  Phase 4 gate: the prosody→haptic mapping is monotonic (louder→stronger, higher→sharper), and
//  the adaptive VAD latches onto speech-like energy and releases on silence.
//

import Testing
@testable import AuraLink_AI

struct ProsodyMapperTests {

    @Test func intensityIsMonotonicInLoudness() {
        var previous: Float = -1
        for db in stride(from: Float(-60), through: 0, by: 4) {
            let p = ProsodyMapper.parameters(energyDB: db, f0Hz: 150, voiced: true)
            #expect(p.intensity >= previous)     // non-decreasing with loudness
            previous = p.intensity
        }
        // Endpoints saturate to the full range.
        #expect(ProsodyMapper.parameters(energyDB: -60, f0Hz: 150, voiced: true).intensity == 0)
        #expect(ProsodyMapper.parameters(energyDB: 0, f0Hz: 150, voiced: true).intensity == 1)
    }

    @Test func sharpnessIsMonotonicInPitch() {
        var previous: Float = -1
        for f0 in stride(from: Float(80), through: 320, by: 20) {
            let p = ProsodyMapper.parameters(energyDB: -20, f0Hz: f0, voiced: true)
            #expect(p.sharpness >= previous)      // non-decreasing with pitch
            previous = p.sharpness
        }
    }

    @Test func unvoicedFallsBackToDullSharpness() {
        let p = ProsodyMapper.parameters(energyDB: -20, f0Hz: nil, voiced: false)
        #expect(p.sharpness == ProsodyMapper.unvoicedSharpness)
    }

    @Test func parametersStayInUnitRange() {
        for db in stride(from: Float(-80), through: 20, by: 10) {
            for f0 in [Float(50), 150, 500] {
                let p = ProsodyMapper.parameters(energyDB: db, f0Hz: f0, voiced: true)
                #expect(p.intensity >= 0 && p.intensity <= 1)
                #expect(p.sharpness >= 0 && p.sharpness <= 1)
            }
        }
    }
}

struct VoiceActivityDetectorTests {

    @Test func silenceStaysUnvoiced() {
        var vad = VoiceActivityDetector(initialFloorDB: -55)
        var anyVoiced = false
        for _ in 0..<50 { anyVoiced = vad.process(energyDB: -58) || anyVoiced }
        #expect(!anyVoiced)
    }

    @Test func loudSpeechLatchesVoicedThenReleasesOnSilence() {
        var vad = VoiceActivityDetector()
        // Establish a quiet floor.
        for _ in 0..<20 { _ = vad.process(energyDB: -55) }

        var voicedDuringSpeech = false
        for _ in 0..<20 { voicedDuringSpeech = vad.process(energyDB: -20) || voicedDuringSpeech }
        #expect(voicedDuringSpeech)

        // Sustained silence releases (after the offFrames debounce).
        var stillVoiced = true
        for _ in 0..<30 { stillVoiced = vad.process(energyDB: -60) }
        #expect(!stillVoiced)
    }

    @Test func onsetIsDebounced() {
        var vad = VoiceActivityDetector(config: {
            var c = VoiceActivityDetector.Config(); c.onFrames = 3; return c
        }(), initialFloorDB: -55)
        for _ in 0..<10 { _ = vad.process(energyDB: -55) }
        // A single loud window must not immediately latch voiced.
        #expect(vad.process(energyDB: -20) == false)
    }
}

struct SoundEventMapperTests {

    @Test func mapsAlarmToAlertUrgency() {
        let event = SoundEventMapper.event(identifier: "smoke_detector_smoke_alarm", confidence: 0.6, timeSeconds: 1)
        #expect(event?.category == .alarm)
        #expect(event?.urgency == .alert)
    }

    @Test func ignoresIrrelevantClasses() {
        #expect(SoundEventMapper.event(identifier: "cupboard_open_or_close", confidence: 0.9, timeSeconds: 0) == nil)
    }

    @Test func lowConfidenceIsDropped() {
        // Below the base bar for a non-alert class.
        #expect(SoundEventMapper.event(identifier: "dog_bark", confidence: 0.2, timeSeconds: 0) == nil)
    }

    @Test func alertClassesUseALowerConfidenceBar() {
        // A siren at moderate confidence still surfaces (safety-biased).
        let event = SoundEventMapper.event(identifier: "civil_defense_siren", confidence: 0.45, timeSeconds: 0)
        #expect(event?.urgency == .alert)
    }
}
