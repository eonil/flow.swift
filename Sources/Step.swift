//
//  Step.swift
//  Flow3
//
//  Created by Hoon H. on 2016/10/08.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Foundation
import Dispatch

extension DispatchQueue {
    /// Starts a new clean-flow from on this queue.
    func flow() -> CleanStep<()> {
        return CleanStep(q: self)
    }
}

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
final class Step<T> {
    private let cs: CleanStep<DirtyStepResult<T>>

    init(q: DispatchQueue) {
        cs = CleanStep(q: q)
    }
    private init(cs: CleanStep<DirtyStepResult<T>>) {
        self.cs = cs
    }
    deinit {
        let message = "You must `cleanse` any potential error. See class documentation for more details."
        cs.preconditionContinuationFlag(toBe: true, andSet: (), message: message)
    }

    /// - Note:
    ///     Unused (dirty) `Step` implies possible unhandled error.
    ///     That must be handled. Compiler will warn on this unhandled returning step.
    func transfer(to queue: DispatchQueue) -> Step<T> {
        return Step(cs: cs.transfer(to: queue))
    }
    /// - Note:
    ///     Unused (dirty) `Step` implies possible unhandled error.
    ///     That must be handled. Compiler will warn on this unhandled returning step.
    func step<U>(_ processResult: @escaping (T) throws -> (U)) -> (Step<U>) {
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
    /// - Note:
    ///     Unused (dirty) `Step` implies possible unhandled error.
    ///     That must be handled. Compiler will warn on this unhandled returning step.
    func step<U>(_ processPromise: @escaping (Step<T>) -> Step<U>) -> (Step<U>){
        let cs2 = cs.step { (cs1: CleanStep<DirtyStepResult<T>>) -> (CleanStep<DirtyStepResult<U>>) in
            return processPromise(Step(cs: cs1)).cs
        }
        return Step<U>(cs: cs2)
    }
    @discardableResult
    func cleanse(_ handleError: @escaping (Error) -> T) -> (CleanStep<T>) {
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
final class CleanStep<T> {
    fileprivate let q: DispatchQueue
    /// Result is `nil` until it to be resolved.
    /// And unresolved result WILL NOT be exposed publicly
    /// by interface design.
    private var result: T?
    fileprivate private(set) var alreadyBeenContinued = atomic_flag()
    fileprivate init(q: DispatchQueue) {
        atomic_flag_clear(&alreadyBeenContinued)
        self.q = q
    }
    fileprivate func preconditionContinuationFlag(toBe desiredState: Bool, andSet: (), message: String? = nil) {
        let oldValue = atomic_flag_test_and_set_explicit(&alreadyBeenContinued, memory_order_seq_cst)
        if let m = message {
            precondition(oldValue == desiredState, m)
        }
        else {
            precondition(oldValue == desiredState)
        }
    }
    @discardableResult
    func transfer(to queue: DispatchQueue) -> CleanStep<T> {
        preconditionContinuationFlag(toBe: false, andSet: ())
        let nextStep = CleanStep<T>(q: queue)
        // We need to wait until the result to be resolved.
        // Processing for current step already been enqueued
        // into `q`. So this block will be executed later then the processing.
        q.async {
            // And then, enqueue into destination queue.
            // Retain the target queue to make it alive.
            queue.async {
                // Captures `self` to make it alive until next continuation.
                nextStep.result = self.result
                // Prevents unwanted lifetime extension of result value.
                self.result = nil
            }
        }
        return nextStep
    }
    /// - Note:
    ///     This is the only way to obtain final result from a `Step`.
    @discardableResult
    func step<U>(_ processResult: @escaping (T) -> (U)) -> CleanStep<U> {
        preconditionContinuationFlag(toBe: false, andSet: ())
        let nextFlow = CleanStep<U>(q: q)
        // We need to wait until the result to be resolved.
        // Processing for current step already been enqueued
        // into `q`. So this block will be executed later then the processing.
        q.async {
            // Captures `self` to make it alive until next continuation.
            precondition(self.result != nil)
            guard let result1 = self.result else { return }
            let result2 = processResult(result1)
            nextFlow.result = result2
            // Prevents unwanted lifetime extension of result value.
            self.result = nil
        }
        return nextFlow
    }
    /// - Returns:
    ///     Returning `Step` is not guaranteed to be same or different `Step` with that is returned
    ///     from `processPromise`.
    @discardableResult
    func step<U>(_ processPromise: @escaping (CleanStep<T>) -> (CleanStep<U>)) -> CleanStep<U> {
        preconditionContinuationFlag(toBe: false, andSet: ())
        let nextFlow = CleanStep<U>(q: q)
        // We need to wait until the result to be resolved.
        // Processing for current step already been enqueued
        // into `q`. So this block will be executed later then the processing.
        q.async {
            // Captures `self` to make it alive until next continuation.
            precondition(self.result != nil)
            let s1 = processPromise(self)
            _ = s1.step { (result: U) -> () in
                nextFlow.result = result
            }
            // Prevents unwanted lifetime extension of result value.
            self.result = nil
        }
        return nextFlow
    }
}
