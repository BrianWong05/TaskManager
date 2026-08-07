// TaskManagerTests/RingBufferTests.swift
// Ring-buffer behavior (spec §4.2, §8): fixed 60-sample window, FIFO order,
// overwrite semantics.

import Testing
@testable import TaskManager

@Suite struct RingBufferTests {
    @Test func appendsInOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.values == [1, 2])
        #expect(buffer.count == 2)
        #expect(buffer.latest == 2)
    }

    @Test func overwritesOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        #expect(buffer.values == [3, 4, 5]) // oldest dropped, order preserved
        #expect(buffer.count == 3)
        #expect(buffer.latest == 5)
    }

    @Test func sixtySecondWindowSemantics() {
        var buffer = RingBuffer<Double>(capacity: 60)
        for i in 1...120 { buffer.append(Double(i)) }
        let values = buffer.values
        #expect(values.count == 60)
        #expect(values.first == 61)
        #expect(values.last == 120)
    }

    @Test func clearResets() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.clear()
        #expect(buffer.values.isEmpty)
        #expect(buffer.latest == nil)
        buffer.append(9)
        #expect(buffer.values == [9])
    }
}
