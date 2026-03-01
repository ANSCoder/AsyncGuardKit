import XCTest
@testable import AsyncGuardKit

final class ScopeTests: XCTestCase {

    func testCancelAllCancelsAllBoundTasks() async throws {
        let lifetime = AsyncLifetime()
        let counter = CancelCounter()

        for _ in 0..<5 {
            AsyncTask {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    await counter.increment()
                }
            }
            .bind(to: lifetime)
        }

        try await Task.sleep(nanoseconds: 60_000_000)
        lifetime.cancelAll()
        try await Task.sleep(nanoseconds: 120_000_000)

        let cancelled = await counter.value
        XCTAssertEqual(cancelled, 5, "All 5 bound tasks must be cancelled")
    }

    func testLifetimeCountIsAccurate() async throws {
        let lifetime = AsyncLifetime()

        for _ in 0..<3 {
            AsyncTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            .bind(to: lifetime)
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(lifetime.count, 3, "Lifetime must track 3 bound tasks")

        lifetime.cancelAll()
        XCTAssertEqual(lifetime.count, 0, "Lifetime must be empty after cancelAll()")
    }

    func testLifetimeCancelAllThenRebind() async throws {
        let lifetime = AsyncLifetime()
        let counter = CancelCounter()

        // First batch
        for _ in 0..<3 {
            AsyncTask {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    await counter.increment()
                }
            }
            .bind(to: lifetime)
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        lifetime.cancelAll()
        try await Task.sleep(nanoseconds: 100_000_000)

        let firstBatch = await counter.value
        XCTAssertEqual(firstBatch, 3)

        // Second batch — lifetime must still be usable after cancelAll
        let expectation = XCTestExpectation(description: "Second batch completes")
        AsyncTask {
            try? await Task.sleep(nanoseconds: 20_000_000)
            expectation.fulfill()
        }
        .bind(to: lifetime)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSetCancellableStoreAndCancelAll() async throws {
        var cancellables = Set<AsyncCancellable>()
        let counter = CancelCounter()

        for _ in 0..<4 {
            AsyncTask {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    await counter.increment()
                }
            }
            .store(in: &cancellables)
        }

        XCTAssertEqual(cancellables.count, 4)

        try await Task.sleep(nanoseconds: 30_000_000)
        cancellables.cancelAll()
        try await Task.sleep(nanoseconds: 150_000_000)

        let cancelled = await counter.value
        XCTAssertEqual(cancelled, 4)
        XCTAssertTrue(cancellables.isEmpty)
    }
}
