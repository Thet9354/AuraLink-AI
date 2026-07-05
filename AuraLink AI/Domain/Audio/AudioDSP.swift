//
//  AudioDSP.swift
//  AuraLink AI
//
//  Short-time acoustic analysis over a window of mono Float samples. Pure functions (Accelerate
//  for the heavy inner products) so the whole DSP core is unit-testable with synthetic signals.
//
//  Pitch (f0) uses normalized autocorrelation: a periodic signal correlates strongly with itself
//  at a lag equal to its period, so the first strong autocorrelation peak in the human-voice lag
//  range gives the fundamental. A clarity threshold on the peak height doubles as a voiced/unvoiced
//  gate — noise has no sharp autocorrelation peak.
//

import Accelerate

nonisolated enum AudioDSP {

    /// Human-voice pitch search range.
    static let minPitchHz: Double = 80
    static let maxPitchHz: Double = 400
    /// Normalized-autocorrelation peak below this is treated as unvoiced (no clear pitch).
    static let voicingClarityThreshold: Float = 0.3
    /// Floor for the dB conversion so digital silence maps to a finite value.
    static let silenceFloorDB: Float = -160

    /// Root-mean-square amplitude of the window.
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    /// Short-time energy in decibels (20·log10 RMS), floored at `silenceFloorDB`.
    static func energyDecibels(_ samples: [Float]) -> Float {
        let r = rms(samples)
        return r > 1e-9 ? 20 * log10f(r) : silenceFloorDB
    }

    /// Fraction of adjacent sample pairs that cross zero, in [0,1].
    static func zeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count where (samples[i] >= 0) != (samples[i - 1] >= 0) {
            crossings += 1
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    /// Estimated fundamental frequency via normalized autocorrelation, or nil if unvoiced/silent.
    static func fundamentalFrequency(_ samples: [Float], sampleRate: Double) -> Float? {
        let n = samples.count
        guard n > 2, sampleRate > 0 else { return nil }

        let minLag = max(1, Int(sampleRate / maxPitchHz))
        let maxLag = min(n - 1, Int(sampleRate / minPitchHz))
        guard maxLag > minLag else { return nil }

        // Zero-lag autocorrelation = window energy; silence has none.
        var energy: Float = 0
        vDSP_dotpr(samples, 1, samples, 1, &energy, vDSP_Length(n))
        guard energy > 1e-6 else { return nil }

        var bestLag = -1
        var bestClarity: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for lag in minLag...maxLag {
                var correlation: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &correlation, vDSP_Length(n - lag))
                let clarity = correlation / energy
                if clarity > bestClarity {
                    bestClarity = clarity
                    bestLag = lag
                }
            }
        }

        guard bestLag > 0, bestClarity >= voicingClarityThreshold else { return nil }
        return Float(sampleRate / Double(bestLag))
    }

    /// Full per-window feature extraction.
    static func features(_ samples: [Float], sampleRate: Double, timeSeconds: Double) -> AudioFeatures {
        let f0 = fundamentalFrequency(samples, sampleRate: sampleRate)
        return AudioFeatures(energyDB: energyDecibels(samples),
                             zeroCrossingRate: zeroCrossingRate(samples),
                             f0Hz: f0,
                             isVoiced: f0 != nil,
                             timeSeconds: timeSeconds)
    }
}
