import SwiftUI
import AsyncGuardKit

struct ContentView: View {
    @State private var logs: [String] = []

    // AsyncLifetime tied to this view's state — all tasks cancel when view disappears
    @State private var lifetime = AsyncLifetime()

    var body: some View {
        NavigationView {
            List(logs, id: \.self) { line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
            }
            .navigationTitle("AsyncGuardKit Demo")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Lifetime") { runLifetimeDemo() }
                    Button("SingleFlight") { runSingleFlight() }
                    Button("Retry") { runRetryDemo() }
                    Button("Cancel All") { cancelAll() }
                }
            }
            .onDisappear {
                // All bound tasks cancel automatically when view disappears
                lifetime.cancelAll()
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func log(_ message: String) {
        logs.append(message)
    }

    private func cancelAll() {
        lifetime.cancelAll()
        Task { @MainActor in log("⛔ All tasks cancelled") }
    }

    // MARK: - Demo 1: Lifetime Binding
    //
    // Shows how AsyncTask.bind(to:) eliminates manual cancellation.
    // All tasks here are cancelled together when "Cancel All" is tapped
    // or when the view disappears — zero cleanup code required.

    private func runLifetimeDemo() {
        Task { @MainActor in log("── Lifetime demo started ──") }

        // Task 1: completes normally
        AsyncTask {
            try await Task.sleep(for: .milliseconds(300))
            await log("✅ Task 1 completed")
        }
        .bind(to: lifetime)

        // Task 2: longer running — will be cancelled if "Cancel All" tapped
        AsyncTask {
            do {
                await log("⏳ Task 2 started (5s — tap Cancel All)")
                try await Task.sleep(for: .seconds(5))
                await log("✅ Task 2 completed")
            } catch is CancellationError {
                await log("⛔ Task 2 cancelled")
            }
        }
        .bind(to: lifetime)

        // Task 3: store(in:) pattern — same result, Combine-familiar syntax
        var cancellables = Set<AnyCancellable>()
        AsyncTask {
            try await Task.sleep(for: .milliseconds(600))
            await log("✅ Task 3 completed (via store(in:))")
        }
        .store(in: &cancellables)
        // cancellables.cancelAll() — call this when you need manual control
    }

    // MARK: - Demo 2: Single Flight
    //
    // 5 concurrent callers request the same "token".
    // withSingleFlight executes the operation ONCE.
    // All 5 callers receive the same result.

    private func runSingleFlight() {
        AsyncTask {
            await log("── SingleFlight demo started ──")

            await withTaskGroup(of: Void.self) { group in
                for index in 0..<5 {
                    group.addTask {
                        let value = try? await withSingleFlight(key: "demo-token") {
                            // This block runs exactly once, regardless of 5 callers
                            try await Task.sleep(for: .milliseconds(250))
                            return "token-abc-\(Int.random(in: 1000...9999))"
                        }
                        await log("caller \(index) → \(value ?? "nil")")
                    }
                }
            }

            // All 5 callers receive the SAME token value — operation ran once
            await log("── SingleFlight demo ended ──")
        }
        .bind(to: lifetime)
    }

    // MARK: - Demo 3: Retry with Backoff
    //
    // Simulates a flaky network call that fails twice then succeeds.
    // retry() handles the loop, backoff, and cancellation automatically.
    private func runRetryDemo() {
        AsyncTask {
            let counter = AttemptCounter()
            do {
                let result = try await retry(
                    attempts: 4,
                    backoff: .exponential(base: .milliseconds(200))
                ) {
                    let attempt = await counter.increment()
                    await log("attempt \(attempt)...")

                    if attempt < 3 {
                        throw URLError(.networkConnectionLost)
                    }

                    return "data-loaded"
                }

                await log("Retry succeeded: \(result)")
            } catch {
                let finalCount = await counter.current()
                await log("Retry failed after \(finalCount) attempts: \(error)")
            }
        }
        .bind(to: lifetime)
    }
}

#Preview {
    ContentView()
}
