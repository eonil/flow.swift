Flow
====
Hoon H.

[![Build Status](https://api.travis-ci.org/eonil/flow.swift.svg)](https://travis-ci.org/eonil/flow.swift)


This is Flow version 3.

Basically a copy of BoltsSwift with these additional features.

- Warn and check if you didn't handle potential error.
- Simplified interface. Only 3 methods. No more bunch of 
  `continueWith...` methods.
- Major class name is not `Task` to avoid name ambiguity with 
  `Foundation.Task` in Swift 3.

But this library requires you to always designated execution queue.

Quickstart by Examples
----------------------
Here's an example.

    DispatchQueue.main
        .flow(with: 1)
        .step({ $0 + 2 })
        .step({ print($0); assert($0 == 3) })

Does these.

1. Start with `1`.
2. Continue to add `2`.
3. Print `3` and assert.

Another example.

    DispatchQueue.main
        .flow(with: 1)
        .transfer(to: DispatchQueue.global())
        .step({ $0 + 2 })
        .transfer(to: DispatchQueue.main)
        .step({ print($0); assert($0 == 3) })

Does these.

1. Start with `1` in main GCD queue.
2. Shift execution to some global GCD queue.
3. Continue to add `2`.
4. Shift back to main GCD queue.
5. Print `3` and assert.

Of course, you can start from non-main GCD queue.

    DispatchQueue.global()
        .flow(with: 1)
        .transfer(to: DispatchQueue.main)
        .step({ $0 + 2 })
        .transfer(to: DispatchQueue.global())
        .step({ print($0); assert($0 == 3) })

Let's try asynchronous waiting flow.
Here's an example.

    DispatchQueue.main
        .flow(with: 1)
        .step({ r, signal in
            DispatchQueue.global()
                .asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
                    assert(Thread.isMainThread == false)
                    signal(r + 2)
                }
        })
        .step({ print($0); assert($0 == 3 && Thread.isMainThread) })

Which does this.

1. Start with `1` in main GCD queue.
2. Wait in some global GCD queue for about 3 seconds.
3. SHIFT BACK to main GCD queue.
4. Print `3` and assert.

Notice that the flow will shift back to original GCD queue regardless
of the asynchronous execution finished.

Actually such waiting feature is already included. Here's an example which 
does exactly same thing.

    DispatchQueue.main
        .flow(with: 1)
        .wait(for: .seconds(3))
        .transfer(to: DispatchQueue.global())
        .step({ $0 + 2 })
        .transfer(to: DispatchQueue.main)
        .step({ print($0); assert($0 == 3 && Thread.isMainThread) })










Credits
-------
This library is written by Hoon H., Eonil.
Thanks to BoltsSwift library to inspire me to write this.



License
-------
MIT License.




















