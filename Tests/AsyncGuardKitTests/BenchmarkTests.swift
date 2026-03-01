import XCTest
@testable import AsyncGuardKit

/// Performance benchmarks for AsyncGuardKit primitives.
///
/// These tests do not assert pass/fail thresholds — they print timing
/// to the test log so you can track overhead over time. Run with
/// `swift test` and inspect the console output.
final class BenchmarkTests: XCTestCase {

    func testAsyncTaskBindOverhead() async throws {
        let iterations = 500
        let clock = ContinuousClock()
        let lifetime = AsyncLifetime()

        let start = clock.now
        for _ in 0..<iterations {
            AsyncTask { }.bind(to: lifetime)
        }
        let elapsed = start.duration(to: clock.now)
        lifetime.cancelAll()

        print("[Benchmark] AsyncTask.bind x\(iterations): \(elapsed)")
    }

    func testAsyncTaskStoreInSetOverhead() async throws {
        let iterations = 500
        let clock = ContinuousClock()
        var cancellables = Set<AsyncCancellable>()

        let start = clock.now
        for _ in 0..<iterations {
            AsyncTask { }.store(in: &cancellables)
        }
        let elapsed = start.duration(to: clock.now)
        cancellables.cancelAll()

        print("[Benchmark] AsyncTask.store x\(iterations): \(elapsed)")
    }

    func testSingleFlightCoordinationOverhead() async throws {
        let clock = ContinuousClock()

        let start = clock.now
        _ = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<200 {
                group.addTask {
                    try await withSingleFlight(key: "bench-key") { 42 }
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        let elapsed = start.duration(to: clock.now)

        print("[Benchmark] withSingleFlight 200-call coordination: \(elapsed)")
    }

    func testRetryNoBackoffOverhead() async throws {
        let iterations = 200
        let clock = ContinuousClock()

        let start = clock.now
        for _ in 0..<iterations {
            _ = try await retry(attempts: 1) { 1 }
        }
        let elapsed = start.duration(to: clock.now)

        print("[Benchmark] retry(attempts:1) x\(iterations): \(elapsed)")
    }

    func testLifetimeCancelAllCost() async throws {
        let lifetime = AsyncLifetime()

        for _ in 0..<200 {
            AsyncTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            .bind(to: lifetime)
        }

        let clock = ContinuousClock()
        let start = clock.now
        lifetime.cancelAll()
        let elapsed = start.duration(to: clock.now)

        print("[Benchmark] AsyncLifetime.cancelAll() for 200 tasks: \(elapsed)")
    }
}
