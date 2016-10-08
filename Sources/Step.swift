//
//  Step.swift
//  Flow
//
//  Created by Hoon H. on 2016/10/08.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Foundation
import Dispatch

public extension DispatchQueue {
    /// Starts a new clean-flow from on this queue.
    public func flow() -> CleanStep<()> {
        return CleanStep(q: self)
    }
    public func flow<T>(with initialValue: T) -> CleanStep<T> {
        return CleanStep(q: self, result: initialValue)
    }
}

//public final class StepController<T> {
//    private(set) var step: Step<T>
//    init(queue: DispatchQueue) {
//        step = Step(q: queue)
//    }
//    func signal(_ result: T) {
//        step.signal(result: .ok(result))
//    }
//    func halt(_ error: Error) {
//        step.signal(result: .error(error))
//    }
//}
//
//public final class CleanStepController<T> {
//    private(set) var step: CleanStep<T>
//    init(queue: DispatchQueue) {
//        step = CleanStep(q: queue)
//    }
//    func signal(_ result: T) {
//        step.signal(result: result)
//    }
//}

/// A flow stepping which can throw some error.
///
/// This is stepping of a dirty-flow. Dirty-flow mean it can become an error.
/// On any error, any further stepping will be ignored until it meet `cleanse` call.
///
/// Because this flow CAN result an error, and it's not safe to ignore such error.
/// This flow utilizes compiler's warning feature on unused return value to warn
/// such situation. You MUST handle any returned (dirty) stepping.
/// This flow also uses dynamic check for any unhandled error.
///
/// So, always continue any (dirty) stepping into a `CleanStep`. Use `cleanse` method
/// to continue to a clean step.
///
public final class Step<T> {
    private let cs: CleanStep<DirtyStepResult<T>>

    init(q: DispatchQueue) {
        cs = CleanStep(q: q)
    }
    fileprivate init(cs: CleanStep<DirtyStepResult<T>>) {
        self.cs = cs
    }
    deinit {
        assert(cs.alreadyBeenContinued, "You must `cleanse` any potential error. See class documentation for more details.")
        SteppingErrorReporting.handler(.badStateOnDeinit)
    }

    var queue: DispatchQueue {
        return cs.queue
    }
    /// Signal and continue.
    fileprivate func signal(result: DirtyStepResult<T>) {
        cs.signal(result: result)
    }

    /// - Note:
    ///     Unused (dirty) `Step` implies possible unhandled error.
    ///     That must be handled. Compiler will warn on this unhandled returning step.
    public func transfer(to queue: DispatchQueue) -> Step<T> {
        return Step(cs: cs.transfer(to: queue))
    }
    /// - Note:
    ///     Unused (dirty) `Step` implies possible unhandled error.
    ///     That must be handled. Compiler will warn on this unhandled returning step.
    public func step<U>(_ processResult: @escaping (T) throws -> (U)) -> (Step<U>) {
        let cs1 = cs.step { (r: DirtyStepResult<T>) -> (DirtyStepResult<U>) in
            switch r {
            case .error(let err):
                return .error(err)
            case .ok(let r1):
                do {
                    let r2 = try processResult(r1)
                    return .ok(r2)
                }
                catch let err {
                    return .error(err)
                }
            }
        }
        return Step<U>(cs: cs1)
    }
//    /// - Note:
//    ///     Unused (dirty) `Step` implies possible unhandled error.
//    ///     That must be handled. Compiler will warn on this unhandled returning step.
//    public func step<U>(_ processPromise: @escaping (Step<T>) -> Step<U>) -> (Step<U>){
//        let cs2 = cs.step { (cs1: CleanStep<DirtyStepResult<T>>) -> (CleanStep<DirtyStepResult<U>>) in
//            return processPromise(Step(cs: cs1)).cs
//        }
//        return Step<U>(cs: cs2)
//    }
    @discardableResult
    public func step<U>(_ process: @escaping (_ result: T, _ signal: @escaping (U) -> ()) throws -> ()) -> Step<U> {
        let cs1 = cs.step { (r: DirtyStepResult<T>, signal: @escaping (DirtyStepResult<U>) -> ()) in
            do {
                switch r {
                case .ok(let r1):
                    try process(r1) { (r2: U) in
                        signal(.ok(r2))
                    }
                case .error(let err):
                    signal(.error(err))
                }
            }
            catch let err {
                signal(.error(err))
            }
        }
        return Step<U>(cs: cs1)
    }
    @discardableResult
    public func cleanse(_ handleError: @escaping (Error) -> T) -> (CleanStep<T>) {
        return cs.step { (r: DirtyStepResult<T>) -> (T) in
            switch r {
            case .error(let err):
                return handleError(err)
            case .ok(let r1):
                return r1
            }
        }
    }
}
private enum DirtyStepResult<T> {
    case error(Error)
    case ok(T)
}

/// A flow stepping which CANNOT throw any error.
///
/// Because this flow cannot result an error, it's fine to discard any result
/// safely.
///
/// Any continuation operations are allowed only once and mutually exclusive.
/// This is checked by debug mode assertion.
///
/// Flow stepping will extend lifetime of specified `DispatchQueue` until everything
/// to be executed. Which implies the flow stepping are unstoppable program.
///
/// - Note:
///     I assume;
///     - DispatchSemaphore will create OS threads.
///     - Using of many semaphores will create many OS threads. That's unwanted.
///     - Avoid use of semaphore.
///
/// - Note:
///     Utilizes GCD queue's serial FIFO execution guarantee.
///
public final class CleanStep<T> {
    private var ssm: SteppingStateMachine<T>
    fileprivate init(q: DispatchQueue) {
        ssm = SteppingStateMachine(in: q)
    }
    fileprivate init(q: DispatchQueue, result: T) {
        ssm = SteppingStateMachine(in: q, state: SteppingState<T>.unscheduledButSignaled(result))
    }
    deinit {
        // We don't need validation here 
        // because clean flow is fine to stop at anywhere
        // because it doesn't imply any error.
    }
    var queue: DispatchQueue {
        return ssm.queue
    }
    fileprivate var alreadyBeenContinued: Bool {
        switch ssm.state {
        case .unscheduledAndUnsignaled:     return false
        case .unscheduledButSignaled(_):    return false
        case .unsignaledButScheduled(_):    return true
        case .processingOrDisposed:         return true
        }
    }
    /// Signal and continue.
    fileprivate func signal(result: T) {
        ssm.signal(result)
    }

    @discardableResult
    public func transfer(to queue: DispatchQueue) -> CleanStep<T> {
        let cs1 = CleanStep<T>(q: queue)
        ssm.waitSignalAndContinue { (r: T) in
            cs1.ssm.signal(r)
        }
        return cs1
    }
    /// - Note:
    ///     This is the only way to obtain final result from a `Step`.
    @discardableResult
    public func step<U>(_ processResult: @escaping (T) -> (U)) -> CleanStep<U> {
        let cs1 = CleanStep<U>(q: ssm.queue)
        ssm.waitSignalAndContinue { (r: T) in
            let r1 = processResult(r)
            cs1.ssm.signal(r1)
        }
        return cs1
    }
//    /// DO NOT expose this method publicly.
//    /// This method exists only to support dirty stepping.
//    ///
//    /// - Returns:
//    ///     Returning `Step` is not guaranteed to be same or different `Step` with that is returned
//    ///     from `processPromise`.
//    @discardableResult
//    fileprivate func step<U>(_ processPromise: @escaping (CleanStep<T>) -> (CleanStep<U>)) -> CleanStep<U> {
//        let cs1 = CleanStep<U>(q: ssm.queue)
//        ssm.waitSignalAndContinue { (r: T) in
//            // Captures `self` to make it alive until next continuation.
//            let s1 = processPromise(self)
//            s1.ssm.waitSignalAndContinue({ (r1: U) in
//                cs1.ssm.signal(r1)
//            })
//        }
//        return cs1
//    }

    @discardableResult
    public func step<U>(_ process: @escaping (_ result: T, _ signal: @escaping (U) -> ()) -> ()) -> CleanStep<U> {
        let cs1 = CleanStep<U>(q: ssm.queue)
        ssm.waitSignalAndContinue { (r: T) in
            process(r) { r1 in
                cs1.signal(result: r1)
            }
        }
        return cs1
    }
//    public func step<U>(_ process: @escaping (_ result: T, _ signal: @escaping (U) -> ()) throws -> ()) -> Step<U> {
//        let s1 = Step<U>(q: ssm.queue)
//        ssm.waitSignalAndContinue { (r: T) in
//            do {
//                try process(r) { r1 in
//                    s1.signal(result: .ok(r1))
//                }
//            }
//            catch let err {
//                s1.signal(result: .error(err))
//            }
//        }
//        return s1
//    }
    fileprivate func dirtify() -> Step<T> {
        let s1 = Step<T>(q: queue)
        step { s1.signal(result: .ok($0)) }
        return s1
    }
}
















public extension Step {
    public func wait(for duration: DispatchTimeInterval) -> Step {
        let q = queue
        let cs1 = step { (r: T, signal: @escaping (T) -> ()) in
            let t = DispatchTime.now() + duration
            q.asyncAfter(deadline: t, execute: { signal(r) })
        }
        return cs1
    }
    public func wait<U>(for anotherFlow: CleanStep<U>) -> Step<(T,U)> {
        let s1 = anotherFlow.dirtify()
        let s2 = wait(for: s1)
        return s2
    }
    /// - Note:
    ///     Any of current or another flow becomes an error
    ///     returning step becomes an error, and partial result
    ///     will be abandoned.
    public func wait<U>(for anotherFlow: Step<U>) -> Step<(T,U)> {
        let s1 = Step<(T,U)>(q: queue)
        // Continue `anotherFlow` immediately to preserve continuation.
        // This helps to prevent weird bugs due to execution order.
        let anotherFlow1 = anotherFlow.step(passthrough)
        step { (r: T) throws -> () in
            _ = anotherFlow1.step({ (r1: U) in s1.signal(result: .ok((r, r1))) })
            .cleanse({ s1.signal(result: .error($0)) })
        }.cleanse { (err: Error) in
            _ = anotherFlow1.step({ _ in s1.signal(result: .error(err)) })
        }
        return s1
    }
    public func wait(for anotherFlow: Step<()>) -> Step<T> {
        return wait(for: anotherFlow).step({ $0.0 })
    }
}
public extension CleanStep {
    public func wait(for duration: DispatchTimeInterval) -> CleanStep {
        let q = queue
        let cs1 = step { (r: T, signal: @escaping (T) -> ()) in
            let t = DispatchTime.now() + duration
            q.asyncAfter(deadline: t, execute: { signal(r) })
        }
        return cs1
    }
    public func wait<U>(for anotherFlow: CleanStep<U>) -> CleanStep<(T,U)> {
        let cs1 = CleanStep<(T,U)>(q: queue)
        // Continue `anotherFlow` immediately to preserve continuation.
        // This helps to prevent weird bugs due to execution order.
        let anotherFlow1 = anotherFlow.step(passthrough)
        step { (r: T, signal: () -> ()) in
            anotherFlow1.step({ (r1: U) in
                cs1.signal(result: (r, r1))
            })
        }
        return cs1
    }
    public func wait(for anotherFlow: CleanStep<()>) -> CleanStep<T> {
        return wait(for: anotherFlow).step({ $0.0 })
    }
}

private func passthrough<T>(_ a: T) -> T {
    return a
}











