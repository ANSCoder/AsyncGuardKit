# AsyncGuardKit – Design Document

## Status
Implemented — v1.0.0

## Authors
Anand (ANSCoder)

---

## Introduction

AsyncGuardKit is a lightweight Swift package that provides coordination primitives built on top of Swift’s structured concurrency model.

It standardizes three coordination patterns commonly reimplemented in application code:

- Task lifetime ownership
- Concurrent work deduplication (single-flight pattern)
- Cancellation-aware retry with structured backoff

AsyncGuardKit does not replace Swift concurrency. It builds on `Task`, actors, and cooperative cancellation to provide safer coordination for real-world applications.

---

## Motivation

Swift introduced structured concurrency in Swift 5.5, including:

- `async` / `await`
- `Task`
- `TaskGroup`
- Actors
- Cooperative cancellation

These primitives are powerful. However, application-level coordination issues remain common:

### 1. Task Lifetime Ownership

Tasks created inside view models, controllers, or services often outlive their intended owner unless explicitly cancelled.

This can lead to:

- Mutations on stale state
- Crashes from unintended access
- Difficult-to-reason-about cancellation flows

### 2. Duplicate Concurrent Work

Multiple concurrent callers may trigger identical work (e.g., token refresh), causing:

- Redundant network calls
- Race conditions
- Wasted resources

### 3. Retry Boilerplate

Retry logic with delay and cancellation awareness is frequently hand-written and inconsistent across codebases.

AsyncGuardKit standardizes these coordination concerns.

---

## Goals

AsyncGuardKit aims to:

- Preserve Swift structured concurrency semantics
- Avoid implicit actor hopping
- Provide deterministic task lifetime binding
- Provide safe, actor-backed single-flight deduplication
- Provide cancellation-aware retry with configurable backoff
- Remain lightweight and dependency-free
- Offer optional debug diagnostics without release overhead

---

## Non-Goals

AsyncGuardKit does not:

- Replace `Task`, `Actor`, or `MainActor`
- Introduce new language features
- Provide reactive stream composition
- Automatically route execution contexts
- Replace Combine or async sequences
- Abstract away Swift concurrency primitives

---

## Proposed API

### Task Lifetime Binding

```swift
public final class AsyncTask
public final class AsyncLifetime
````

Example:

```swift
final class FeedViewModel {
    private let lifetime = AsyncLifetime()

    func load() {
        AsyncTask {
            let items = try await api.fetchFeed()
            await MainActor.run { self.items = items }
        }
        .bind(to: lifetime)
    }
}
```

Tasks bound to an `AsyncLifetime` are cancelled automatically when the lifetime deallocates.

---

### Single-Flight Deduplication

```swift
public func withSingleFlight<Key: Hashable & Sendable, T: Sendable>(
    key: Key,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T
```

Concurrent callers sharing the same key await a single underlying execution.

Example:

```swift
let token = try await withSingleFlight(key: "token-refresh") {
    try await auth.refreshToken()
}
```

Implementation details:

* Actor-backed registry
* Key includes both caller key and result type
* Entry removed after completion (success or failure)

---

### Retry with Backoff

```swift
public func retry<T: Sendable>(
    attempts: Int,
    backoff: RetryBackoff = .none,
    shouldRetry: @Sendable (Error) -> Bool = { _ in true },
    operation: @escaping @Sendable () async throws -> T
) async throws -> T
```

Backoff strategies:

```swift
public enum RetryBackoff {
    case none
    case fixed(Duration)
    case exponential(base: Duration)
}
```

Behavior:

* Cancellation-aware
* Propagates `CancellationError` immediately
* Stops retry loop if parent task is cancelled
* Optional conditional retry via `shouldRetry`

---

## Detailed Design

### AsyncTask

`AsyncTask` wraps a `Task<Void, Never>` and provides explicit lifetime strategies:

* `bind(to:)`
* `store(in:)`
* `detached()`

It does not alter execution context. Actor isolation remains fully under caller control.

---

### AsyncLifetime

`AsyncLifetime` owns a collection of `AsyncCancellable` tasks.

Responsibilities:

* Cancel all bound tasks on `deinit`
* Support explicit `cancelAll()`
* Allow rebinding after cancellation

This eliminates manual `deinit` cleanup in common view model patterns.

---

### Single-Flight Registry

An internal actor-backed registry maintains in-flight tasks keyed by:

* Caller-provided key
* Result type identifier

Concurrent requests for matching keys suspend and await the same task.

Entries are removed after completion.

---

### Retry

The retry loop:

* Checks cancellation before each attempt
* Applies delay via `Task.sleep`
* Respects `shouldRetry`
* Throws the final error if all attempts fail

---

## Concurrency Model

AsyncGuardKit:

* Does not introduce implicit context switching
* Does not override actor isolation
* Relies entirely on cooperative cancellation
* Preserves structured concurrency guarantees

All shared mutable state is protected by actors or explicit synchronization.

---

## Source Compatibility

AsyncGuardKit is a standalone Swift Package.

No language-level changes are introduced.

---

## ABI Stability

Not applicable. This is not part of the Swift standard library.

---

## Alternatives Considered

1. Raw `Task` usage everywhere
   Leads to repeated coordination boilerplate.

2. Reactive frameworks
   Solve stream composition, not structured task lifetime coordination.

3. Custom global registries
   Often introduce race conditions and weak lifecycle boundaries.

---

## Future Directions

* Timeout coordination primitives
* Metrics and tracing hooks
* Observability integration
* Structured cancellation hierarchies

---

## Conclusion

AsyncGuardKit provides a minimal coordination layer over Swift structured concurrency. It improves lifecycle safety, eliminates duplicate work, and standardizes retry logic — while preserving Swift’s native concurrency semantics.
