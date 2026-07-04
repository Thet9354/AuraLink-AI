//
//  AudioRingBufferTests.swift
//  AuraLink AITests
//
//  Phase 1 gate: the lock-free SPSC audio ring buffer must read back exactly what was written,
//  including across the modulo wrap-around boundary, and must drop (not corrupt) when full.
//

import Testing
@testable import AuraLink_AI

struct AudioRingBufferTests {

    private func write(_ ring: AudioRingBuffer, _ values: [Float]) -> Int {
        var values = values
        return values.withUnsafeBufferPointer { ring.write($0) }
    }

    private func read(_ ring: AudioRingBuffer, count: Int) -> [Float] {
        var out = [Float](repeating: -1, count: count)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        return Array(out.prefix(n))
    }

    @Test func writeThenReadRoundTrips() {
        let ring = AudioRingBuffer(capacity: 8)
        let wrote = write(ring, [1, 2, 3, 4, 5])
        #expect(wrote == 5)
        #expect(ring.availableToRead == 5)

        let out = read(ring, count: 5)
        #expect(out == [1, 2, 3, 4, 5])
        #expect(ring.availableToRead == 0)
    }

    @Test func readsCorrectlyAcrossWrapAround() {
        let ring = AudioRingBuffer(capacity: 8)
        // Advance both indices to 5 so the next write straddles the modulo boundary.
        _ = write(ring, [1, 2, 3, 4, 5])
        _ = read(ring, count: 5)

        let wrote = write(ring, [6, 7, 8, 9, 10, 11])   // occupies storage indices 5,6,7,0,1,2
        #expect(wrote == 6)

        let out = read(ring, count: 6)
        #expect(out == [6, 7, 8, 9, 10, 11])            // proves wrap-around correctness
    }

    @Test func dropsWhenFull() {
        let ring = AudioRingBuffer(capacity: 4)
        let wrote = write(ring, [1, 2, 3, 4, 5, 6])
        #expect(wrote == 4)                              // only capacity samples accepted
        #expect(ring.availableToRead == 4)

        let out = read(ring, count: 10)
        #expect(out == [1, 2, 3, 4])                     // no corruption of accepted samples
    }

    @Test func partialReadLeavesRemainder() {
        let ring = AudioRingBuffer(capacity: 8)
        _ = write(ring, [10, 20, 30, 40])

        let first = read(ring, count: 2)
        #expect(first == [10, 20])
        #expect(ring.availableToRead == 2)

        let second = read(ring, count: 5)
        #expect(second == [30, 40])
        #expect(ring.availableToRead == 0)
    }

    @Test func totalWrittenTracksAcceptedSamples() {
        let ring = AudioRingBuffer(capacity: 4)
        _ = write(ring, [1, 2, 3])
        _ = read(ring, count: 3)
        _ = write(ring, [4, 5])
        #expect(ring.totalWritten == 5)
    }
}
