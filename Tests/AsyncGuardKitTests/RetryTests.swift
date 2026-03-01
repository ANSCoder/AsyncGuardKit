import XCTest
@testable import AsyncGuardKit

final class RetryTests: XCTestCase {

    // MARK: - Helpers

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
        func incrementAndReturn() -> Int { value += 1; return value }
    }

    // MARK: - Basic behavior

    func testSucceedsOnFirstAttempt() async throws {
        let counter = Counter()
        let result = try await retry(attempts: 3) {
            await counter.increment()
            return "success"
        }
        XCTAssertEqual(result, "success")
        let count = await counter.value
        XCTAssertEqual(count, 1, "Should call operation exactly once on first success")
    }

    func testExhaustsAllAttemptsOnPersistentFailure() async throws {
        struct AlwaysFails: Error {}
        let counter = Counter()

        do {
            _ = try await retry(attempts: 3, backoff: .none) {
                await counter.increment()
                throw AlwaysFails()
            }
            XCTFail("Should have thrown")
        } catch is AlwaysFails {
            let count = await counter.value
            XCTAssertEqual(count, 3, "Should attempt exactly 3 times")
        }
    }

    func testSucceedsAfterInitialFailures() async throws {
        let counter = Counter()

        let result = try await retry(attempts: 5, backoff: .none) {
            let n = await counter.incrementAndReturn()
            if n < 3 { throw URLError(.networkConnectionLost) }
            return "eventual-success"
        }

        XCTAssertEqual(result, "eventual-success")
        let count = await counter.value
        XCTAssertEqual(count, 3, "Should succeed on third attempt")
    }

    // MARK: - Backoff

    func testFixedBackoffDelayIsRespected() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        _ = try? await retry(attempts: 3, backoff: .fixed(.milliseconds(80))) {
            throw Fail()
        }

        let elapsed = start.duration(to: clock.now)
        // 2 delays of 80ms = 160ms minimum
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(140),
            "Fixed backoff should accumulate ~160ms for 3 attempts")
    }

    func testExponentialBackoffGrows() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        _ = try? await retry(attempts: 3, backoff: .exponential(base: .milliseconds(50))) {
            throw Fail()
        }

        let elapsed = start.duration(to: clock.now)
        // attempt 0 fails → 50ms, attempt 1 fails → 100ms = ~150ms total
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(130),
            "Exponential backoff: 50ms + 100ms = ~150ms for 3 attempts")
    }

    func testNoBackoffIsImmediate() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        _ = try? await retry(attempts: 5, backoff: .none) { throw Fail() }

        let elapsed = start.duration(to: clock.now)
        XCTAssertLessThan(elapsed, .milliseconds(100),
            ".none backoff should complete near-instantly")
    }

    // MARK: - shouldRetry predicate

    func testShouldRetryPredicateStopsOnFatalError() async throws {
        struct Retryable: Error {}
        struct Fatal: Error {}
        let counter = Counter()

        do {
            _ = try await retry(attempts: 5, backoff: .none, shouldRetry: { $0 is Retryable }) {
                let n = await counter.incrementAndReturn()
                if n == 1 { throw Retryable() }
                throw Fatal()
            }
        } catch is Fatal {
            let count = await counter.value
            XCTAssertEqual(count, 2, "Should stop retrying when shouldRetry returns false")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShouldRetryFalseOnFirstAttemptThrowsImmediately() async throws {
        struct Fail: Error {}
        let counter = Counter()

        do {
            _ = try await retry(attempts: 5, backoff: .none, shouldRetry: { _ in false }) {
                await counter.increment()
                throw Fail()
            }
        } catch is Fail {
            let count = await counter.value
            XCTAssertEqual(count, 1, "shouldRetry=false should prevent any retry")
        }
    }

    // MARK: - Cancellation

    func testCancellationStopsRetryLoop() async throws {
        let counter = Counter()

        let task = Task {
            _ = try? await retry(attempts: 20, backoff: .fixed(.milliseconds(200))) {
                await counter.increment()
                throw URLError(.networkConnectionLost)
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000) // let first attempt fire
        task.cancel()
        _ = await task.result

        let count = await counter.value
        XCTAssertLessThan(count, 10, "Cancelled retry should not run all 20 attempts")
    }

    func testCancellationErrorNotRetried() async throws {
        let counter = Counter()

        let task = Task {
            _ = try? await retry(attempts: 5, backoff: .none) {
                await counter.increment()
                try Task.checkCancellation()
                return "ok"
            }
        }

        task.cancel()
        _ = await task.result

        let count = await counter.value
        XCTAssertLessThanOrEqual(count, 1, "CancellationError must not trigger a retry")
    }
}
