import XCTest
@testable import AsyncGuardKit

final class SingleFlightTests: XCTestCase {

    func testConcurrentCallsExecuteOnce() async throws {
        let counter = CallCounter()

        let results = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await withSingleFlight(key: "token") {
                        await counter.increment()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        return 99
                    }
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(results.count, 20, "All 20 callers must receive a result")
        XCTAssertTrue(results.allSatisfy { $0 == 99 }, "All callers must receive the same result")

        let callCount = await counter.value
        XCTAssertEqual(callCount, 1, "Operation must execute exactly once")

        let inFlight = await SingleFlightRegistry.shared.inFlightCount()
        XCTAssertEqual(inFlight, 0, "Registry must be clean after completion")
    }

    func testAllCallersReceiveSameResult() async throws {
        var results: [String] = []
        let lock = NSLock()

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    (try? await withSingleFlight(key: "shared-result") {
                        try await Task.sleep(nanoseconds: 50_000_000)
                        return "shared-value"
                    }) ?? "nil"
                }
            }
            for await result in group {
                lock.withLock { results.append(result) }
            }
        }

        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0 == "shared-value" })
    }

    func testErrorPropagationToAllCallers() async {
        let errorCounter = CallCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        try await withSingleFlight(key: "error-key") {
                            try await Task.sleep(nanoseconds: 10_000_000)
                            throw SampleError.failed
                        }
                    } catch is SampleError {
                        await errorCounter.increment()
                    } catch {}
                }
            }
        }

        let count = await errorCounter.value
        XCTAssertEqual(count, 5, "All 5 callers must receive the error")

        let inFlight = await SingleFlightRegistry.shared.inFlightCount()
        XCTAssertEqual(inFlight, 0, "Registry must be clean after failure")
    }

    func testDistinctKeysRunIndependently() async throws {
        let counter = CallCounter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await withSingleFlight(key: "key-a") {
                    await counter.increment()
                    return "a"
                }
            }
            group.addTask {
                _ = try await withSingleFlight(key: "key-b") {
                    await counter.increment()
                    return "b"
                }
            }
            for try await _ in group {}
        }

        let count = await counter.value
        XCTAssertEqual(count, 2, "Distinct keys must each execute their operation independently")
    }

    func testRegistryCleanAfterSuccess() async throws {
        _ = try await withSingleFlight(key: "cleanup-ok") { return "done" }
        let inFlight = await SingleFlightRegistry.shared.inFlightCount()
        XCTAssertEqual(inFlight, 0)
    }
}

private enum SampleError: Error { case failed }
