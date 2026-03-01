import XCTest
@testable import AsyncGuardKit

final class IntegrationTests: XCTestCase {

    /// Simulates a real-world ViewModel: multiple tasks bound to a lifetime,
    /// single-flight deduplication on a shared resource, automatic cancellation on release.
    func testViewModelPattern() async throws {
        var lifetime: AsyncLifetime? = AsyncLifetime()
        let counter = CallCounter()
        let resultsActor = ResultsActor()

        // 10 tasks all requesting the same resource via singleFlight
        for _ in 0..<10 {
            AsyncTask {
                let value = try? await withSingleFlight(key: "viewmodel-resource") {
                    await counter.increment()
                    try await Task.sleep(nanoseconds: 25_000_000)
                    return 42
                }
                if let value { await resultsActor.append(value) }
            }
            .bind(to: lifetime!)
        }

        try await Task.sleep(nanoseconds: 150_000_000)

        // Operation should have run once, all 10 tasks got the result
        let callCount = await counter.value
        XCTAssertEqual(callCount, 1, "singleFlight must deduplicate across all bound tasks")

        let results = await resultsActor.values
        XCTAssertEqual(results.count, 10, "All 10 tasks must receive the result")
        XCTAssertTrue(results.allSatisfy { $0 == 42 })

        // Simulate navigation away — all tasks cancelled
        lifetime = nil
    }

    /// Simulates a refresh pattern: cancel in-flight work, restart with new task.
    func testRefreshPattern() async throws {
        let lifetime = AsyncLifetime()
        let counter = CallCounter()

        // Initial load
        AsyncTask {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // long running
                await counter.increment()
            } catch is CancellationError {}
        }
        .bind(to: lifetime)

        try await Task.sleep(nanoseconds: 30_000_000)

        // User triggers refresh — cancel and restart
        lifetime.cancelAll()

        AsyncTask {
            try? await Task.sleep(nanoseconds: 20_000_000)
            await counter.increment()
        }
        .bind(to: lifetime)

        try await Task.sleep(nanoseconds: 150_000_000)

        let count = await counter.value
        XCTAssertEqual(count, 1, "Only the refresh task should complete, not the cancelled initial load")
    }

    /// Simulates a retry + singleFlight networking scenario.
    func testRetryWithSingleFlight() async throws {
        let counter = CallCounter()

        let results = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await withSingleFlight(key: "retry-network") {
                        try await retry(attempts: 3, backoff: .none) {
                            let n = await counter.incrementAndReturn()
                            if n < 3 { throw URLError(.networkConnectionLost) }
                            return "success"
                        }
                    }
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0 == "success" })

        // 3 retry attempts total (not 5×3 — singleFlight deduplicates)
        let callCount = await counter.value
        XCTAssertEqual(callCount, 3, "retry inside singleFlight must deduplicate across all callers")
    }
}

// MARK: - Helpers

private actor ResultsActor {
    private(set) var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}
