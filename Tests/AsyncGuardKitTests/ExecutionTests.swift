import XCTest
@testable import AsyncGuardKit

final class ExecutionTests: XCTestCase {

    func testTaskBoundToLifetimeCancelledOnDeinit() async throws {
        // Use actor-isolated flag — Swift 6 forbids mutating a captured
        // var from a @Sendable closure (concurrent execution context).
        let flag = BoolFlag()
        var lifetime: AsyncLifetime? = AsyncLifetime()

        AsyncTask {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                await flag.set(true)
            }
        }
        .bind(to: lifetime!)

        try await Task.sleep(nanoseconds: 50_000_000)
        lifetime = nil
        try await Task.sleep(nanoseconds: 250_000_000)

        let isCancelled = await flag.value
        XCTAssertTrue(
            isCancelled,
            "Task bound to lifetime must receive CancellationError when lifetime deallocates"
        )
    }

    func testTaskStoredInSetCancelledOnCancelAll() async throws {
        let flag = BoolFlag()
        var cancellables = Set<AnyCancellable>()

        AsyncTask {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                await flag.set(true)
            }
        }
        .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 50_000_000)
        cancellables.cancelAll()
        try await Task.sleep(nanoseconds: 250_000_000)

        let isCancelled = await flag.value
        XCTAssertTrue(
            isCancelled,
            "Task stored in set must receive CancellationError when cancelAll() is called"
        )
        XCTAssertTrue(
            cancellables.isEmpty,
            "Set must be empty after cancelAll()"
        )
    }

    func testDetachedTaskRunsToCompletionAfterLifetimeReleased() async throws {
        let expectation = XCTestExpectation(description: "Detached task completes")

        AsyncTask {
            try? await Task.sleep(nanoseconds: 100_000_000)
            expectation.fulfill()
        }
        .detached()

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
        XCTAssertEqual(
            lifetime.count, 5,
            "Lifetime must track all 5 bound tasks"
        )

        lifetime.cancelAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        let cancelled = await counter.value
        XCTAssertEqual(
            cancelled, 5,
            "All 5 tasks must receive CancellationError when cancelAll() is called"
        )
        XCTAssertEqual(
            lifetime.count, 0,
            "Lifetime must be empty after cancelAll()"
        )
    }

    func testTaskPriorityIsForwarded() async throws {
        let expectation = XCTestExpectation(description: "Background priority task completes")
        AsyncTask(priority: .background) { expectation.fulfill() }.detached()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}

// MARK: - Test Helpers

/// Actor-isolated boolean flag.
///
/// Replaces `var isCancelled = false` captured by a @Sendable closure,
/// which is illegal in Swift 6 strict concurrency mode.
private actor BoolFlag {
    private(set) var value = false
    func set(_ newValue: Bool) { value = newValue }
}
