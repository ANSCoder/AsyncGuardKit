/// A concurrency-safe counter used for retry attempt tracking.
///
/// `AttemptCounter` is an actor that provides serialized, isolated
/// mutation of an integer value. It is designed for use inside
/// concurrently-executing async code where captured mutable state
/// would otherwise violate Swift 6 concurrency rules.
///
/// ## Why this exists
///
/// In Swift 6 language mode, mutating a captured `var` inside
/// concurrently executing code (such as inside `Task`, `retry`,
/// or other async closures) produces a compiler error:
///
/// > Mutation of captured var in concurrently-executing code
///
/// This actor eliminates that issue by isolating state behind
/// an actor boundary, ensuring thread safety and correctness.
///
/// ## Usage
///
/// ```swift
/// let counter = AttemptCounter()
///
/// let result = try await retry(attempts: 3) {
///     let attempt = await counter.increment()
///     print("Attempt \(attempt)")
///     return try await api.call()
/// }
/// ```
///
/// Because `AttemptCounter` is an actor:
///
/// - All access to `value` is serialized.
/// - No data races are possible.
/// - Swift 6 concurrency rules are satisfied.
/// - The counter is safe across multiple concurrent callers.
///
/// ## When to use
///
/// Use `AttemptCounter` when:
///
/// - You need mutable shared state inside async retry loops
/// - You need deterministic attempt indexing
/// - You want to avoid captured `var` mutation errors
///
/// ## Thread Safety
///
/// Fully thread-safe. Actor isolation guarantees exclusive
/// access to internal state.
///
/// - Important: All methods must be accessed with `await`.
actor AttemptCounter {

    /// Internal stored attempt value.
    private var value = 0

    /// Increments the counter and returns the updated value.
    ///
    /// - Returns: The incremented attempt count.
    func increment() -> Int {
        value += 1
        return value
    }

    /// Returns the current counter value without mutating it.
    ///
    /// - Returns: The current attempt count.
    func current() -> Int {
        value
    }
}
