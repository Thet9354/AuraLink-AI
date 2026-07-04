//
//  AudioActor.swift
//  AuraLink AI
//
//  Owns the `AVAudioEngine` input tap and feeds the lock-free ring buffer. The realtime tap block
//  does only a bounded copy into the ring — no allocation, no lock — as required on the audio thread.
//  Downstream DSP (VAD, mel, f0) arrives in Phase 4 and reads from the ring.
//

import AVFoundation

actor AudioActor {

    enum AudioError: Error {
        case microphoneNotAuthorized
    }

    /// Exposed `nonisolated` so a reader can sample capture metrics without an actor hop; the ring
    /// buffer is itself thread-safe (SPSC atomics).
    nonisolated let ringBuffer: AudioRingBuffer

    private let engine = AVAudioEngine()
    private let tapBufferSize: AVAudioFrameCount = 1024
    private var isRunning = false

    /// Default capacity ≈ 1 second at 48 kHz mono.
    init(capacity: Int = 48_000) {
        ringBuffer = AudioRingBuffer(capacity: capacity)
    }

    func start() async throws {
        guard await CaptureAuthorization.ensureMicrophone() else { throw AudioError.microphoneNotAuthorized }
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let ring = ringBuffer
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            // Realtime-safe: bounded copy into the lock-free ring; mono (channel 0) for Phase 1.
            ring.write(UnsafeBufferPointer(start: channels[0], count: count))
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
    }

    /// Total samples captured since launch (for diagnostics).
    func totalCaptured() -> Int { ringBuffer.totalWritten }
}
