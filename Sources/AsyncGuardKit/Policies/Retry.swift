import Foundation

/// Executes an operation, retrying on failure with a configurable backoff strategy.
///
/// `retry` provides a structured, cancellation-aware retry loop. It eliminates
/// the boilerplate of manual retry logic and supports `.none`, `.fixed`, and
/// `.exponential` backoff strategies.
///
/// ## Overview
///
/// ```swift
/// let data = try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) {
///     try await api.fetchData()
/// }
/// ```
///
/// ## Backoff strategies
///
/// ```swift
/// // No delay — retry immediately
/// try await retry(attempts: 3, backoff: .none) { ... }
///
/// // Fixed — wait 500ms between every attempt
/// try await retry(attempts: 3, backoff: .fixed(.milliseconds(500))) { ... }
///
/// // Exponential — 1s, 2s, 4s between attempts
/// try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) { ... }
/// ```
///
/// ## Conditional retry
///
/// Supply `shouldRetry` to retry only on specific error types:
///
/// ```swift
/// try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) {
///     try await api.post(request)
/// } shouldRetry: { error in
///     (error as? URLError)?.code == .networkConnectionLost
/// }
/// ```
///
/// ## Cancellation
///
/// If the enclosing task is cancelled during a retry loop — including
/// during a backoff delay — the loop stops immediately and throws
/// `CancellationError`.
///
/// ## When not to use
///
/// Avoid `retry` for non-idempotent operations where duplicate calls
/// produce unintended side effects.
///
/// - Parameters:
///   - attempts: Maximum number of attempts including the first. Must be ≥ 1.
///   - backoff: The delay strategy between attempts. Defaults to `.none`.
///   - shouldRetry: Returns `true` if the error should trigger a retry.
///     Defaults to retrying on all errors.
///   - operation: The async, throwing operation to execute.
/// - Returns: The value returned by the first successful attempt.
/// - Throws: The error from the final attempt, or `CancellationError` if
///   the enclosing task is cancelled.
public func retry<T: Sendable>(
    attempts: Int,
    backoff: RetryBackoff = .none,
    shouldRetry: @Sendable (Error) -> Bool = { _ in true },
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    precondition(attempts >= 1, "retry(attempts:) requires at least 1 attempt")

    var lastError: Error?

    for attempt in 0..<attempts {
        try Task.checkCancellation()

        do {
            let result = try await operation()
            Diagnostics.log("retry.succeeded", context: "attempt=\(attempt + 1)")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            Diagnostics.log("retry.failed", context: "attempt=\(attempt + 1) error=\(error)")

            let isLastAttempt = attempt == attempts - 1
            guard !isLastAttempt, shouldRetry(error) else { break }

            let delayNanoseconds = backoff.delay(for: attempt)
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
    }

    throw lastError!
}

// MARK: - RetryBackoff

/// A strategy that controls the delay between retry attempts.
///
/// Use with ``retry(attempts:backoff:shouldRetry:operation:)`` to configure
/// how long the retry loop waits between failed attempts.
///
/// ```swift
/// // Immediate retry
/// .none
///
/// // Constant 500ms delay
/// .fixed(.milliseconds(500))
///
/// // Doubles after each attempt: 1s → 2s → 4s
/// .exponential(base: .seconds(1))
/// ```
public enum RetryBackoff: Sendable {

    /// No delay. Retries execute immediately after failure.
    case none

    /// A constant delay applied before every retry.
    ///
    /// - Parameter delay: Duration to wait before each retry attempt.
    case fixed(Duration)

    /// An exponentially increasing delay between attempts.
    ///
    /// The delay for attempt `n` (0-indexed) is `base × 2ⁿ`.
    /// With `base: .seconds(1)`: 1s → 2s → 4s → 8s ...
    ///
    /// - Parameter base: The base duration for the first retry delay.
    case exponential(base: Duration)

    /// Returns the nanosecond delay for a given 0-based attempt index.
    internal func delay(for attempt: Int) -> UInt64 {
        switch self {
        case .none:
            return 0
        case .fixed(let duration):
            return UInt64(max(0, duration.nanoseconds))
        case .exponential(let base):
            let multiplier = UInt64(pow(2.0, Double(attempt)))
            let baseNanos = UInt64(max(0, base.nanoseconds))
            let (result, overflow) = baseNanos.multipliedReportingOverflow(by: multiplier)
            return overflow ? UInt64.max : result
        }
    }
}

// MARK: - Duration nanoseconds

private extension Duration {
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
