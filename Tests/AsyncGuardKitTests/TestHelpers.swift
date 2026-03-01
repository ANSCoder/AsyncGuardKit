import Foundation

/// Shared actor-backed counter for use across all test files.
actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
    func incrementAndReturn() -> Int { value += 1; return value }
}

/// Shared actor-backed cancellation counter.
actor CancelCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
