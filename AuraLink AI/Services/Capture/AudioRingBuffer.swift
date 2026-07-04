//
//  AudioRingBuffer.swift
//  AuraLink AI
//
//  A lock-free single-producer / single-consumer (SPSC) ring buffer of `Float` samples.
//
//  The producer is the Core Audio realtime tap thread, which must never allocate or take a lock;
//  the consumer is the `AudioActor`'s DSP loop. Correctness rests on the SPSC discipline plus
//  acquire/release atomics on the read/write indices: the producer publishes written samples with a
//  releasing store to `writeIndex`, and the consumer observes them with an acquiring load — a
//  textbook happens-before edge, no lock required.
//
//  Indices are monotonic (never wrapped); storage is addressed modulo capacity. `Int` on 64-bit
//  will not overflow within any realistic runtime. `@unchecked Sendable` because the manually
//  managed buffer and the SPSC contract are enforced by convention, not the type system — one of the
//  three audited unsafe boundaries alongside `FrameToken` and `VideoOutputDelegate`.
//

import Synchronization

nonisolated final class AudioRingBuffer: @unchecked Sendable {

    private let storage: UnsafeMutableBufferPointer<Float>
    private let capacity: Int
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let written = Atomic<Int>(0)

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = UnsafeMutableBufferPointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0)
    }

    deinit {
        storage.deallocate()
    }

    /// Producer side (realtime-safe). Copies as many samples as fit; drops the remainder if the
    /// buffer is full. Returns the number of samples written.
    @discardableResult
    func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        let free = capacity - (w - r)
        let toWrite = min(samples.count, free)
        var i = 0
        while i < toWrite {
            storage[(w + i) % capacity] = samples[i]
            i += 1
        }
        writeIndex.store(w + toWrite, ordering: .releasing)
        written.wrappingAdd(toWrite, ordering: .relaxed)
        return toWrite
    }

    /// Consumer side. Copies up to `dst.count` samples into `dst`. Returns the number read.
    @discardableResult
    func read(into dst: UnsafeMutableBufferPointer<Float>) -> Int {
        let r = readIndex.load(ordering: .relaxed)
        let w = writeIndex.load(ordering: .acquiring)
        let available = w - r
        let toRead = min(dst.count, available)
        var i = 0
        while i < toRead {
            dst[i] = storage[(r + i) % capacity]
            i += 1
        }
        readIndex.store(r + toRead, ordering: .releasing)
        return toRead
    }

    /// Samples currently available to the consumer.
    var availableToRead: Int {
        writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .relaxed)
    }

    /// Total samples ever written (for diagnostics / capture-rate verification).
    var totalWritten: Int {
        written.load(ordering: .relaxed)
    }
}
