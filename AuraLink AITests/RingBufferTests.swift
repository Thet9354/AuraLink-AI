//
//  RingBufferTests.swift
//  AuraLink AITests
//
//  The fixed-capacity ring underpinning pose/feature histories: never grows, overwrites oldest,
//  iterates oldest → newest across the wrap boundary.
//

import Testing
@testable import AuraLink_AI

struct RingBufferTests {

    @Test func appendsAndReadsInOrder() {
        var ring = RingBuffer<Int>(capacity: 5)
        ring.append(1)
        ring.append(2)
        ring.append(3)
        #expect(ring.elements == [1, 2, 3])
        #expect(ring.count == 3)
        #expect(ring.newest == 3)
        #expect(!ring.isFull)
    }

    @Test func overwritesOldestWhenFull() {
        var ring = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { ring.append(i) }
        #expect(ring.elements == [3, 4, 5])   // 1 and 2 overwritten
        #expect(ring.count == 3)
        #expect(ring.isFull)
        #expect(ring.newest == 5)
    }

    @Test func orderCorrectAcrossManyWraps() {
        var ring = RingBuffer<Int>(capacity: 4)
        for i in 1...103 { ring.append(i) }
        #expect(ring.elements == [100, 101, 102, 103])
    }

    @Test func removeAllResets() {
        var ring = RingBuffer<Int>(capacity: 3)
        ring.append(1)
        ring.append(2)
        ring.removeAll()
        #expect(ring.isEmpty)
        #expect(ring.elements.isEmpty)
        #expect(ring.newest == nil)
        ring.append(9)
        #expect(ring.elements == [9])
    }
}
