//
//  SteppingErrorReporting.swift
//  EonilFlow
//
//  Created by Hoon H. on 2016/07/10.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Darwin

public enum SteppingError: Error {
    case badStateOnDeinit
    case alreadyWaiting
    case alreadySignaled
    case alreadyExecuted

    case dispatchQueueUnavailable
}
public struct SteppingErrorReporting {
    static var handler: (SteppingError) -> () = { fatalError("\($0)") } {
        willSet {
            if OSAtomicCompareAndSwap32(0, 1, &flag) == false {
                fatalError("You can set this only once.")
            }
        }
    }
}
private var flag = Int32(0)
