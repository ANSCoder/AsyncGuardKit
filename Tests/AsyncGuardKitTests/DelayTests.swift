import XCTest
@testable import AsyncGuardKit

final class DelayTests: XCTestCase {

    // Tests retry backoff delays since that's our delay primitive

    func testFixedBackoffSuspendsForRequestedDuration() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        _ = try? await retry(attempts: 2, backoff: .fixed(.milliseconds(80))) {
            throw Fail()
        }

        let elapsed = start.duration(to: clock.now)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(70), "Fixed backoff must suspend for at least the requested duration")
    }

    func testExponentialBackoffIncreasesBetweenAttempts() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        // base=50ms: attempt 0→50ms, attempt 1→100ms total ~150ms
        _ = try? await retry(attempts: 3, backoff: .exponential(base: .milliseconds(50))) {
            throw Fail()
        }

        let elapsed = start.duration(to: clock.now)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(130), "Exponential backoff must accumulate delay correctly")
    }

    func testRetryRespectsTaskCancellationDuringDelay() async throws {
        struct Fail: Error {}
        let counter = CallCounter()

        let task = Task {
            _ = try? await retry(attempts: 10, backoff: .fixed(.milliseconds(300))) {
                await counter.increment()
                throw Fail()
            }
        }

        // Let first attempt fire, then cancel during backoff delay
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        try await Task.sleep(nanoseconds: 500_000_000)

        let count = await counter.value
        XCTAssertLessThan(count, 5, "Retry loop must stop when task is cancelled during delay")
    }

    func testNoDelayBackoffIsImmediate() async throws {
        struct Fail: Error {}
        let clock = ContinuousClock()
        let start = clock.now

        _ = try? await retry(attempts: 5, backoff: .none) { throw Fail() }

        let elapsed = start.duration(to: clock.now)
        // 5 attempts with no sleep — should complete in well under 100ms
        XCTAssertLessThan(elapsed, .milliseconds(100), ".none backoff must not introduce significant delay")
    }
}
