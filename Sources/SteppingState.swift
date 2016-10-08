//
//  SteppingState.swift
//  EonilFlow
//
//  Created by Hoon H. on 2016/07/07.
//  Copyright © 2016 Eonil. All rights reserved.
//

/// State Diagram
///
/// UU      = `unscheduledAndUnsignaled`
/// Usig    = `unscheduledButSignaled`
/// Ucont   = `unsignaledButScheduled`
/// PD      = `processingOrDisposed`
///
internal enum SteppingState<T> {
    case unscheduledAndUnsignaled
    case unscheduledButSignaled(T)
    case unsignaledButScheduled((T) -> ())
    case processingOrDisposed
}
