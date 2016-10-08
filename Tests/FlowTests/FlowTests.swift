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

        var s = DispatchQueue.main.flow(with: Float(0))
        for op in ops {
            s = s.step { n in
                reduceOp(n: n, op: op)
            }
        }
        let exp = expectation(description: "Wait...")
        s.step { n in
            XCTAssert(n == r1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10) { (err: Error?) in
            if let err = err {
                XCTFail("\(err)")
            }
        }
    }

    @available(OSX 10.11, *)
    static var allTests : [(String, (FlowTests) -> () throws -> Void)] {
        return [
            ("testAll", testAll),
        ]
    }
}


