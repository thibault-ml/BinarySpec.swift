//
//  BinarySpecTests.swift
//  BinarySpecTests
//
//  Created by kennytm on 15-12-05.
//  Copyright © 2015 kennytm. All rights reserved.
//

import XCTest
@testable import BinarySpec

class SliceQueueTest: XCTestCase {
    func testEqual() {
        let queue1 = SliceQueue<Int>([[1,2,3,4,5], [6,7], [8], [9,10], [11,12,13,14,15,16]])
        let queue2 = SliceQueue<Int>([[1,2,3,4], [5,6,7], [8,9,10,11,12,13,14,15,16]])
        let queue3 = SliceQueue<Int>([[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17]])
        let queue4 = SliceQueue<Int>([[1],[2],[3],[4,5,6,7,8,9,-1,-2]])

        XCTAssertEqual(queue1, queue2)
        XCTAssertEqual(queue2, queue1)

        XCTAssertEqual(queue1, queue1)
        XCTAssertEqual(queue2, queue2)
        XCTAssertEqual(queue3, queue3)
        XCTAssertEqual(queue4, queue4)

        XCTAssertNotEqual(queue1, queue3)
        XCTAssertNotEqual(queue1, queue4)
        XCTAssertNotEqual(queue2, queue3)
        XCTAssertNotEqual(queue2, queue4)
        XCTAssertNotEqual(queue3, queue1)
        XCTAssertNotEqual(queue3, queue2)
        XCTAssertNotEqual(queue3, queue4)
        XCTAssertNotEqual(queue4, queue1)
        XCTAssertNotEqual(queue4, queue2)
        XCTAssertNotEqual(queue4, queue3)
    }

    func testRemoveFirst() {
        var queue = SliceQueue<Int>([[1,2,3,4,5], [6,7], [8], [9,10], [11,12,13,14,15,16]])

        let first = queue.removeFirst(4)
        XCTAssertEqual(first, SliceQueue([[1,2,3,4]]))
        XCTAssertEqual(queue, SliceQueue([[5,6,7,8,9,10,11,12,13,14,15,16]]))

        let second = queue.removeFirst(1)
        XCTAssertEqual(second, SliceQueue([[5]]))
        XCTAssertEqual(queue, SliceQueue([[6,7,8,9,10,11,12,13,14,15,16]]))

        let third = queue.removeFirst(4)
        XCTAssertEqual(third, SliceQueue([[6,7,8,9]]))
        XCTAssertEqual(queue, SliceQueue([[10,11,12,13,14,15,16]]))

        let fourth = queue.removeFirst(7)
        XCTAssertEqual(fourth, SliceQueue([[10,11,12,13,14,15,16]]))
        XCTAssertEqual(queue, SliceQueue([]))

        let fifth = queue.removeFirst(4)
        XCTAssertNil(fifth)
    }

    func testRemoveFirstWithNotEnoughData() {
        var queue = SliceQueue<Int>([[1,2,3], [4,5,6]])

        let first = queue.removeFirst(20)
        XCTAssertNil(first)
        XCTAssertEqual(queue, SliceQueue([[1,2,3,4,5,6]]))

        let second = queue.removeFirst(4)
        XCTAssertEqual(second, SliceQueue([[1,2,3,4]]))
        XCTAssertEqual(queue, SliceQueue([[5,6]]))

        let third = queue.removeFirst(4)
        XCTAssertNil(third)
        XCTAssertEqual(queue, SliceQueue([[5,6]]))
    }
}
