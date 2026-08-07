// Data/RingBuffer.swift
// Uniform fixed-capacity ring buffer for resource history (spec §4.2):
// 60 samples × 1 s per resource, ephemeral — cleared on restart.

import Foundation

struct RingBuffer<Element>: Sendable where Element: Sendable {
    let capacity: Int
    private var storage: [Element]
    private var start = 0   // index of the oldest element
    private(set) var count = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = []
        storage.reserveCapacity(capacity)
    }

    mutating func append(_ element: Element) {
        if count < capacity {
            storage.append(element)
            count += 1
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    mutating func clear() {
        storage.removeAll(keepingCapacity: true)
        start = 0
        count = 0
    }

    /// Oldest → newest order, suitable for charting.
    var values: [Element] {
        guard count == capacity else { return Array(storage) }
        return Array(storage[start..<capacity]) + Array(storage[0..<start])
    }

    var latest: Element? {
        guard count > 0 else { return nil }
        let index = count < capacity ? count - 1 : (start + capacity - 1) % capacity
        return storage[index]
    }
}
