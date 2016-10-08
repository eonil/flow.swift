//
//  SteppingStateMachine.swift
//  EonilFlow
//
//  Created by Hoon H. on 2016/07/07.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Dispatch

/// Flow is designed for single serial execution flow.
/// Which means, each flow object can signal or wait only once.
/// Otherwise, it's all invalid progression, and all becomes an
/// error.
///
/// It's possible to handle all of these errors by making all of
/// state change functions to `throw`, but it would take too much
/// programmer concern, and gains small because these errors are
/// very unlikely to happen. Also, when these errors occur, usually
/// there's no good way to handle them except ignoring.
///
/// Here's my approach.
///
/// 1. A flow can wait without throwing error. If someone try to wait
///     multiple times, it becomes no-op and triggers global error
///     handler.
/// 2. A flow can signal with error throwing.
/// 1. Invalid state progression becomes no-op.
/// 2. Program reports the error through global `SteppingErrorReport`
///     immediately (synchronously) in the thread. If the programmer
///     really want to handle them, they can do this with it.
///
internal struct SteppingStateMachine<T> {
    typealias Parameter = T
    let queue: DispatchQueue
    private var _state: SteppingState<T>

    /// 0 = no accessor.
    /// 1 = some thread took access.
    private var flag = Int32(0)

    init(in queue: DispatchQueue, state: SteppingState<T> = .unscheduledAndUnsignaled) {
        self.queue = queue
        _state = state
    }
    var state: SteppingState<T> {
        mutating get {
            return executeWithFlagLocking { _state }
        }
    }
    /// Creates a new state-machine which will continue on signal.
    mutating func waitSignalAndContinue(_ f: @escaping (T) -> ()) {
        executeWithFlagLocking {
            switch _state {
            case .unscheduledAndUnsignaled:
                _state = .unsignaledButScheduled(f)
            case .unscheduledButSignaled(let v):
                _state = .processingOrDisposed
                queue.async(execute: { f(v) })
            case .unsignaledButScheduled(_):
                SteppingErrorReporting.handler(.alreadyWaiting)
            case .processingOrDisposed:
                SteppingErrorReporting.handler(.alreadyExecuted)
            }
        }
    }
    mutating func signal(_ v: T) {
        executeWithFlagLocking {
            switch _state {
            case .unscheduledAndUnsignaled:
                _state = .unscheduledButSignaled(v)
            case .unscheduledButSignaled(_):
                SteppingErrorReporting.handler(.alreadySignaled)
            case .unsignaledButScheduled(let c):
                _state = .processingOrDisposed
                queue.async(execute: { c(v) })
            case .processingOrDisposed:
                SteppingErrorReporting.handler(.alreadyExecuted)
            }
        }
    }
    private mutating func executeWithFlagLocking<T>(_ f: () -> T) -> T {
        while OSAtomicCompareAndSwap32Barrier(0, 1, &flag) == false {
            usleep(1)
        }
        let r = f()
        let ok = OSAtomicCompareAndSwap32Barrier(1, 0, &flag)
        precondition(ok == true)
        return r
    }
}

extension SteppingStateMachine {
    func waitingSignalAndConinue(_ c: @escaping (T) -> ()) -> SteppingStateMachine {
        var sm = self
        sm.waitSignalAndContinue(c)
        return sm
    }
    func signaled(_ s: T) -> SteppingStateMachine {
        var sm = self
        sm.signal(s)
        return sm
    }
}

//extension SteppingStateMachine {
//    mutating func validateDeinit() {
//        switch state {
//        case .unscheduledAndUnsignaled:
//            SteppingErrorReporting.handler(.badStateOnDeinit)
//        case .unscheduledButSignaled(_):
//            // Fine. Just a terminal flow.
//            break
//        case .unsignaledButScheduled(_):
//            SteppingErrorReporting.handler(.badStateOnDeinit)
//        case .processingOrDisposed:
//            // Fine.
//            break
//        }
//    }
//}
