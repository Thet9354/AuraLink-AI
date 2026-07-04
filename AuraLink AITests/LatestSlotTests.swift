//
//  LatestSlotTests.swift
//  AuraLink AITests
//
//  Verifies the back-pressure contract of the pipeline's core concurrency primitive:
//  latest-value semantics, single-slot bounded memory, and non-blocking producer.
//

import Testing
@testable import AuraLink_AI

struct LatestSlotTests {

    @Test func takeReturnsPutValue() async {
        let slot = LatestSlot<Int>()
        await slot.put(42)
        let value = await slot.take()
        #expect(value == 42)
    }

    @Test func latestValueWinsAndSlotEmptiesAfterTake() async {
        let slot = LatestSlot<Int>()
        await slot.put(1)
        await slot.put(2)
        await slot.put(3)

        let value = await slot.take()
        #expect(value == 3)          // intermediate 1 and 2 were dropped — back-pressure

        let empty = await slot.isEmpty
        #expect(empty)
    }

    @Test func parkedConsumerResumesOnPut() async {
        let slot = LatestSlot<Int>()
        async let pending = slot.take()          // parks: slot is empty
        try? await Task.sleep(for: .milliseconds(20))
        await slot.put(7)
        let value = await pending
        #expect(value == 7)
    }

    @Test func cancelledParkedTakeReturnsNil() async {
        let slot = LatestSlot<Int>()
        let task = Task { await slot.take() }
        try? await Task.sleep(for: .milliseconds(20))   // let the consumer park
        task.cancel()
        let value = await task.value
        #expect(value == nil)
    }

    @Test func floodedProducerNeverGrowsAndConsumerSeesLatest() async {
        let slot = LatestSlot<Int>()
        // Producer pushes 1000 values without ever suspending on a full buffer: memory stays
        // bounded to a single slot, and a later take observes only the freshest value.
        for i in 1...1000 {
            await slot.put(i)
        }
        let value = await slot.take()
        #expect(value == 1000)

        let empty = await slot.isEmpty
        #expect(empty)
    }
}
