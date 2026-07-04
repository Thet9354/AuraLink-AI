//
//  RingBuffer.swift
//  AuraLink AI
//
//  A fixed-capacity, value-type ring buffer for time-series state (pose windows, feature
//  histories). Appending beyond capacity overwrites the oldest element — the buffer never grows,
//  which is the hot-loop memory rule. Pure Domain type: no locks, no framework imports; each
//  owning actor keeps its own instance as private state.
//

nonisolated struct RingBuffer<Element> {

    private var storage: [Element?]
    private var nextIndex = 0          // where the next append lands
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    var isFull: Bool { count == capacity }
    var isEmpty: Bool { count == 0 }

    mutating func append(_ element: Element) {
        storage[nextIndex] = element
        nextIndex = (nextIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Elements ordered oldest → newest.
    var elements: [Element] {
        guard count > 0 else { return [] }
        let start = (nextIndex - count + capacity) % capacity
        return (0..<count).compactMap { storage[(start + $0) % capacity] }
    }

    /// The most recently appended element.
    var newest: Element? {
        guard count > 0 else { return nil }
        return storage[(nextIndex - 1 + capacity) % capacity]
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        nextIndex = 0
        count = 0
    }
}
