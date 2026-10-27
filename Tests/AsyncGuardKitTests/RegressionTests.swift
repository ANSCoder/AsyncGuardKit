import XCTest
@testable import AsyncGuardKit

final class RegressionTests: XCTestCase {

    func testExponentialBackoffSaturatesInsteadOfTrapping() {
        let backoff = RetryBackoff.exponential(base: .seconds(1))
        XCTAssertEqual(backoff.delay(for: 3), .seconds(8))
        XCTAssertGreaterThan(backoff.delay(for: 200), .seconds(1_000_000))
    }

    func testFinishedTasksLeaveLifetime() async throws {
        let lifetime = AsyncLifetime()
        AsyncTask { }.bind(to: lifetime)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(lifetime.count, 0)
    }

    func testCancellingLastWaiterCancelsSharedOperation() async throws {
        let cancelled = CancelCounter()
        let caller = Task {
            try await withSingleFlight(key: "cancel-propagation") {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { await cancelled.increment(); throw error }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        caller.cancel()
        _ = try? await caller.value
        try await Task.sleep(for: .milliseconds(50))
        let count = await cancelled.value
        let inFlight = await SingleFlightRegistry.shared.inFlightCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(inFlight, 0)
    }
}
