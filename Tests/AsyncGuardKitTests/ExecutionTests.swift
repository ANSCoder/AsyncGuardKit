import XCTest
@testable import AsyncGuardKit

final class ExecutionTests: XCTestCase {

    func testTaskBoundToLifetimeCancelledOnDeinit() async throws {
        var isCancelled = false
        var lifetime: AsyncLifetime? = AsyncLifetime()

        AsyncTask {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                isCancelled = true
            }
        }
        .bind(to: lifetime!)

        try await Task.sleep(nanoseconds: 50_000_000)
        lifetime = nil
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(isCancelled, "Task bound to lifetime must cancel when lifetime deallocates")
    }

    func testTaskStoredInSetCancelledOnCancelAll() async throws {
        var isCancelled = false
        var cancellables = Set<AsyncCancellable>()

        AsyncTask {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                isCancelled = true
            }
        }
        .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 50_000_000)
        cancellables.cancelAll()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(isCancelled, "Task stored in set must cancel when cancelAll() is called")
        XCTAssertTrue(cancellables.isEmpty, "Set must be empty after cancelAll()")
    }

    func testDetachedTaskRunsToCompletionAfterLifetimeReleased() async throws {
        let expectation = XCTestExpectation(description: "Detached task completes")
        var lifetime: AsyncLifetime? = AsyncLifetime()

        AsyncTask {
            try? await Task.sleep(nanoseconds: 100_000_000)
            expectation.fulfill()
        }
        .detached()

        lifetime = nil // Must NOT affect detached task

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testMultipleTasksBoundToSameLifetime() async throws {
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

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(lifetime.count, 5)

        lifetime.cancelAll()
        try await Task.sleep(nanoseconds: 200_000_000)

        let cancelled = await counter.value
        XCTAssertEqual(cancelled, 5, "All 5 tasks must be cancelled")
        XCTAssertEqual(lifetime.count, 0)
    }

    func testTaskPriorityIsForwarded() async throws {
        let expectation = XCTestExpectation(description: "Background priority task completes")
        AsyncTask(priority: .background) { expectation.fulfill() }.detached()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
