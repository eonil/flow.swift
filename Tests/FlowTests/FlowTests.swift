import XCTest
import GameplayKit
@testable import Flow

class FlowTests: XCTestCase {
    func testPlatformVersion() {
        XCTAssert({
            if #available(OSX 10.11, *) { return true }
            else { return false }
        }())
    }
    @available(OSX 10.11, *)
    func testREADMEExamples() {
        func assert(_ f: Bool) {
            XCTAssert(f)
        }
        do {
            DispatchQueue.main
                .flow(with: 1)
                .step({ $0 + 2 })
                .step({ print($0); assert($0 == 3) })
        }
        do {
            DispatchQueue.main
                .flow(with: 1)
                .transfer(to: DispatchQueue.global())
                .step({ $0 + 2 })
                .transfer(to: DispatchQueue.main)
                .step({ print($0); assert($0 == 3) })
        }

        do {
            DispatchQueue.global()
                .flow(with: 1)
                .transfer(to: DispatchQueue.main)
                .step({ $0 + 2 })
                .transfer(to: DispatchQueue.global())
                .step({ print($0); assert($0 == 3) })
        }

        do {
            let time = Date()
            let exp = expectation(description: "Waiting about 3 seconds.")
            DispatchQueue.main
                .flow(with: 1)
                .step({ r, signal in
                    DispatchQueue.global()
                        .asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
                            signal(r + 2)
                    }
                })
                .step({ print($0); assert($0 == 3 && Thread.isMainThread) })
                .step({ _ -> () in exp.fulfill() })
            waitForExpectations(timeout: 10, handler: { (err: Error?) in
                XCTAssert(err == nil, "\(err!)")
                let time1 = Date()
                let interval = time1.timeIntervalSince(time)
                XCTAssert(interval > 2.0)
                XCTAssert(interval < 4.0)
            })
        }

        do {
            let time = Date()
            let exp = expectation(description: "Waiting about 3 seconds.")
            DispatchQueue.main
                .flow(with: 1)
                .wait(for: .seconds(3))
                .transfer(to: DispatchQueue.global())
                .step({ $0 + 2 })
                .transfer(to: DispatchQueue.main)
                .step({ print($0); assert($0 == 3 && Thread.isMainThread) })
                .step({ _ -> () in exp.fulfill() })
            waitForExpectations(timeout: 10, handler: { (err: Error?) in
                XCTAssert(err == nil, "\(err!)")
                let time1 = Date()
                let interval = time1.timeIntervalSince(time)
                XCTAssert(interval > 2.0)
                XCTAssert(interval < 4.0)
            })
        }
    }
    @available(OSX 10.11, *)
    func testQueueShifting() {
        DispatchQueue.main
            .flow()
            .step({ XCTAssert(Thread.isMainThread == true) })
            .transfer(to: .global())
            .step({ XCTAssert(Thread.isMainThread == false) })
            .transfer(to: .main)
            .step({ XCTAssert(Thread.isMainThread == true) })
    }
    @available(OSX 10.11, *)
    func testAll() {
        let prng = GKARC4RandomSource(seed: Data([0,0,0,0]))
        enum Op {
            case add(Float)
            case mul(Float)
        }
        func genFloat32ExceptZero() -> Float {
            let n = prng.nextUniform()
            guard n != 0 else { return genFloat32ExceptZero() }
            return n
        }
        func genOp() -> Op {
            let n = abs(prng.nextInt()) % 2
            switch n {
            case 0: return .add(genFloat32ExceptZero())
            case 1: return .mul(genFloat32ExceptZero())
            default: fatalError()
            }
        }
        func reduceOp(n: Float, op: Op) -> Float {
            switch op {
            case .add(let n1):  return n + n1
            case .mul(let n1):  return n * n1
            }
        }
        let ops = Array((0..<1024).map({ _ in genOp() }))
        let r1 = ops.reduce(0, reduceOp)
        let r2 = ops.reduce(0, reduceOp)
        print((r1, r2))
        XCTAssert(r1 == r2)

        // Without waiting.
        do {
            var s = DispatchQueue.main.flow(with: Float(0))
            for op in ops {
                s = s.step { n in
                    reduceOp(n: n, op: op)
                }
            }
            let exp = expectation(description: "Wait...")
            s.step { n in
                print((r1, n))
                XCTAssert(n == r1)
                exp.fulfill()
            }
            waitForExpectations(timeout: 100) { (err: Error?) in
                if let err = err {
                    XCTFail("\(err)")
                }
            }
        }
        // With waiting.
        do {
            let sema = DispatchSemaphore(value: 0)
            var s = DispatchQueue.global().flow(with: Float(0)).step({ (n: Float) -> Float in
                sema.wait()
                return n
            })
            for op in ops {
                s = s.step { n in
                    reduceOp(n: n, op: op)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3), execute: { 
                sema.signal()
            })
            let exp = expectation(description: "Wait...")
            s.step { n in
                print((r1, n))
                XCTAssert(n == r1)
                exp.fulfill()
            }
            waitForExpectations(timeout: 100) { (err: Error?) in
                if let err = err {
                    XCTFail("\(err)")
                }
            }
        }
    }

    @available(OSX 10.11, *)
    static var allTests : [(String, (FlowTests) -> () throws -> Void)] {
        return [
            ("testREADMEExamples", testREADMEExamples),
            ("testQueueShifting", testQueueShifting),
            ("testAll", testAll),
        ]
    }
}


