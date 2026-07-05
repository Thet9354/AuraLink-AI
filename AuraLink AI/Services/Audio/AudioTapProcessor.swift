//
//  AudioTapProcessor.swift
//  AuraLink AI
//
//  The nonisolated bridge from AVAudioEngine's realtime tap into the Swift concurrency world.
//  A single tap fans one buffer out to three consumers, synchronously, on the audio thread:
//    1. the lock-free ring buffer (for DSP / prosody),
//    2. SoundAnalysis (environmental sound events),
//    3. the speech recognition request (live captions).
//
//  `@unchecked Sendable` justification: `SNAudioStreamAnalyzer` and
//  `SFSpeechAudioBufferRecognitionRequest` are not `Sendable`, and `framePosition` is mutable —
//  all are used exclusively on the single serial tap queue AVAudioEngine invokes this on. This is
//  the fourth and last audited unsafe boundary, symmetric with `VideoOutputDelegate`.
//

import AVFoundation
import SoundAnalysis
import Speech

nonisolated final class AudioTapProcessor: @unchecked Sendable {

    private let ring: AudioRingBuffer
    private let analyzer: SNAudioStreamAnalyzer?
    private let speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var framePosition: AVAudioFramePosition = 0

    init(ring: AudioRingBuffer,
         analyzer: SNAudioStreamAnalyzer?,
         speechRequest: SFSpeechAudioBufferRecognitionRequest?) {
        self.ring = ring
        self.analyzer = analyzer
        self.speechRequest = speechRequest
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        autoreleasepool {
            if let channels = buffer.floatChannelData {
                ring.write(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            }
            analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
            speechRequest?.append(buffer)
            framePosition += AVAudioFramePosition(buffer.frameLength)
        }
    }
}
