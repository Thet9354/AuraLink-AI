//
//  AudioDSPTests.swift
//  AuraLink AITests
//
//  Phase 4 gate: DSP correctness on synthetic signals — pitch detection recovers a known sine's
//  frequency, energy tracks amplitude, silence is unvoiced, and ZCR behaves.
//

import Foundation
import Testing
@testable import AuraLink_AI

struct AudioDSPTests {

    private let sampleRate: Double = 48_000

    private func sine(freq: Double, count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { i in amplitude * sinf(Float(2 * Double.pi * freq * Double(i) / sampleRate)) }
    }

    private func noise(count: Int, amplitude: Float = 0.3, seed: UInt64 = 42) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in amplitude * (Float(rng.nextUnit()) * 2 - 1) }
    }

    @Test func recoversPitchOfSineWaves() {
        for target in [110.0, 147.0, 220.0, 330.0] {
            let samples = sine(freq: target, count: 4096)
            let f0 = AudioDSP.fundamentalFrequency(samples, sampleRate: sampleRate)
            let value = try? #require(f0)
            // Within 3% — autocorrelation lag quantization.
            #expect(f0 != nil)
            if let value { #expect(abs(Double(value) - target) / target < 0.03) }
        }
    }

    @Test func silenceHasNoPitch() {
        let silence = [Float](repeating: 0, count: 4096)
        #expect(AudioDSP.fundamentalFrequency(silence, sampleRate: sampleRate) == nil)
    }

    @Test func whiteNoiseIsUnvoiced() {
        // Broadband noise has no sharp autocorrelation peak → no confident pitch.
        let samples = noise(count: 4096)
        #expect(AudioDSP.fundamentalFrequency(samples, sampleRate: sampleRate) == nil)
    }

    @Test func energyTracksAmplitude() {
        let quiet = AudioDSP.energyDecibels(sine(freq: 200, count: 2048, amplitude: 0.05))
        let loud = AudioDSP.energyDecibels(sine(freq: 200, count: 2048, amplitude: 0.8))
        #expect(loud > quiet)
        #expect(quiet.isFinite && loud.isFinite)
    }

    @Test func trueSilenceIsFlooredDecibels() {
        #expect(AudioDSP.energyDecibels([Float](repeating: 0, count: 1024)) == AudioDSP.silenceFloorDB)
    }

    @Test func zeroCrossingRateHigherForHigherPitch() {
        let low = AudioDSP.zeroCrossingRate(sine(freq: 100, count: 4096))
        let high = AudioDSP.zeroCrossingRate(sine(freq: 400, count: 4096))
        #expect(high > low)
    }

    @Test func featuresMarkVoicedForToneUnvoicedForSilence() {
        let voiced = AudioDSP.features(sine(freq: 180, count: 4096), sampleRate: sampleRate, timeSeconds: 0)
        #expect(voiced.isVoiced)
        #expect(voiced.f0Hz != nil)

        let silent = AudioDSP.features([Float](repeating: 0, count: 4096), sampleRate: sampleRate, timeSeconds: 0)
        #expect(!silent.isVoiced)
    }
}

/// Deterministic RNG so noise tests are reproducible.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}
