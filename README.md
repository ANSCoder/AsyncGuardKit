<div align="center">

<img src="assets/banner.png" width="100%" alt="AsyncGuardKit" />

# AsyncGuardKit

**Structured task lifetime management for Swift.**

[![Swift 6](https://img.shields.io/badge/Swift-6.0+-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16+-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![macOS 13+](https://img.shields.io/badge/macOS-13+-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![MIT License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/ANSCoder/AsyncGuardKit/ci.yml?branch=master&style=flat&label=CI)](https://github.com/ANSCoder/AsyncGuardKit/actions)

[Installation](#installation) · [The Problem](#the-problem) · [API](#api) · [Examples](#real-world-patterns) · [Architecture](#architecture) · [Design](#design-principles) · [Contributing](#contributing)

</div>

---

AsyncGuardKit removes the cancellation boilerplate that Swift concurrency leaves to you. Three small, composable primitives — **lifetime-bound tasks**, **single-flight deduplication**, and **cancellation-aware retry** — built for Swift 6 strict concurrency, with zero dependencies.

| | |
|---|---|
| 🔗 **`AsyncTask` + `AsyncLifetime`** | Tasks that are cancelled when their owner goes away |
| 🛫 **`withSingleFlight`** | N concurrent callers → one operation → one shared result |
| 🔁 **`retry`** | Backoff, predicates, overflow-safe, stops the instant you are cancelled |

---

## Why this exists

An unowned `Task {}` keeps running after the screen that started it is gone. A token refresh fired from ten views hits your server ten times. Hand-rolled retry loops forget `CancellationError`. These are the *default* outcome of Swift concurrency without a lifetime strategy.

```swift
// ✅ Owned, cancelled with its owner
AsyncTask { [weak self] in
    let profile = try await api.fetchProfile()
    await self?.apply(profile)
}
.bind(to: lifetime)

// ✅ Ten callers, one refresh
let token = try await withSingleFlight(key: "token-refresh") {
    try await auth.refreshToken()
}

// ✅ Cancellable, composable retry
let data = try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) {
    try await api.call()
}
```

> **Capture `self` weakly.** `AsyncTask` cancels when its `AsyncLifetime` deallocates, but a running task that captures its owner strongly keeps that owner alive. Use `[weak self]` (as above) so deallocation can actually happen.

---

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ANSCoder/AsyncGuardKit", from: "1.0.0")  // check Releases for the latest
]
```

Add to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AsyncGuardKit", package: "AsyncGuardKit")
    ]
)
```

Then import:

```swift
import AsyncGuardKit
```

### Xcode

**File → Add Package Dependencies** → paste the repository URL → select version → **Add Package**.

### Requirements

| Platform | Minimum |
|---|---|
| iOS | 16.0 |
| macOS | 13.0 |
| tvOS | 16.0 |
| watchOS | 9.0 |
| Swift | 6.0 (builds in Swift 6 language mode) |
| Xcode | 16.0 |

---

## API

### `AsyncTask`

A unit of async work with an explicit, declared lifetime strategy. Every `AsyncTask` requires you to choose one of three strategies — there is no silent default. Lifetime intent is visible in the code.

```swift
// Strategy 1 — bind to object lifetime (recommended)
// Cancelled automatically when `lifetime` deallocates.
AsyncTask { await doWork() }
    .bind(to: lifetime)

// Strategy 2 — store in a cancellable set (manual control)
// Cancelled when you call cancellables.cancelAll().
AsyncTask { await doWork() }
    .store(in: &cancellables)

// Strategy 3 — detached (explicit fire-and-forget)
// Runs to completion. Use for logging, analytics.
AsyncTask { await Analytics.log(.screenViewed) }
    .detached()
```

**With priority:**

```swift
AsyncTask(priority: .userInitiated) {
    try await api.fetchCriticalData()
}
.bind(to: lifetime)
```

---

### `AsyncLifetime`

Cancels all bound tasks when it deallocates. Declare it as a `let` property — it lives and dies with its owner. Tasks that finish on their own are released immediately, so `count` reflects only work still in flight.

```swift
@MainActor @Observable
final class FeedViewModel {
    var items: [Item] = []
    private let lifetime = AsyncLifetime()  // one line

    func load() {
        AsyncTask { [weak self] in
            let items = try await api.fetchFeed()
            await self?.apply(items)
        }
        .bind(to: lifetime)
        // ↑ Cancelled when FeedViewModel is released. No deinit needed.
    }

    func refresh() {
        lifetime.cancelAll()  // cancel in-flight, restart fresh
        load()
    }

    private func apply(_ items: [Item]) { self.items = items }
}
```

---

### `Set<AnyCancellable>`

Combine-familiar manual cancellation. Same muscle memory, no Combine dependency. (If you also `import Combine`, qualify the type as `AsyncGuardKit.AnyCancellable`.)

```swift
var cancellables = Set<AnyCancellable>()

AsyncTask { await loadFeed() }.store(in: &cancellables)
AsyncTask { await loadAds() }.store(in: &cancellables)

cancellables.cancelAll()  // cancel and clear
```

---

### `withSingleFlight(key:operation:)`

Execute an operation exactly once for a given key. All concurrent callers for the same key join the in-flight operation and receive the same result — or the same error.

**Cancellation:** cancelling one caller never cancels work others are still waiting on. When the *last* waiter is cancelled, the shared operation is cancelled and the key is freed, so the next call starts fresh.

Named following Apple's `with*` convention (`withTaskGroup`, `withCheckedContinuation`) to make scoping semantics immediately recognizable.

```swift
// One network request. All concurrent callers share the result.
let token = try await withSingleFlight(key: "token-refresh") {
    try await authClient.refreshAccessToken()
}

// Typed keys prevent collisions in large systems
enum APIKey: Hashable {
    case tokenRefresh
    case userProfile(id: String)
    case feedPage(cursor: String)
}

let profile = try await withSingleFlight(key: APIKey.userProfile(id: userID)) {
    try await api.fetchProfile(userID)
}
```

---

### `retry(attempts:backoff:shouldRetry:isolation:operation:)`

Retry with configurable backoff. Stops immediately on `CancellationError`, including during a backoff delay. Exponential delays saturate instead of overflowing, so very high attempt counts are safe. The operation runs on the **caller's actor**, so it can use that actor's non-`Sendable` state without `@Sendable` gymnastics.

```swift
// Exponential: 1s → 2s → 4s
let data = try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) {
    try await api.fetchData()
}

// Fixed: 500ms between each attempt
let result = try await retry(attempts: 5, backoff: .fixed(.milliseconds(500))) {
    try await database.query()
}

// Conditional: only retry on specific errors
let response = try await retry(
    attempts: 3,
    backoff: .exponential(base: .seconds(1)),
    shouldRetry: { ($0 as? URLError)?.code == .networkConnectionLost }
) {
    try await api.post(request)
}
```

**`RetryBackoff` options:**

| Case | Behaviour |
|---|---|
| `.none` | Retry immediately, no delay |
| `.fixed(.milliseconds(500))` | Same delay before every attempt |
| `.exponential(base: .seconds(1))` | `base × 2ⁿ` — doubles after each failure |

---

## Real-world patterns

### SwiftUI search ViewModel

> `@Observable` needs iOS 17+; on iOS 16 use `ObservableObject` + `@Published` — the `AsyncTask` code is identical.

```swift
@MainActor @Observable
final class SearchViewModel {
    var results: [SearchResult] = []
    var isLoading = false

    private let lifetime = AsyncLifetime()

    func search(query: String) {
        lifetime.cancelAll()  // cancel previous search

        AsyncTask { [weak self] in
            await self?.setLoading(true)
            do {
                let results = try await withSingleFlight(key: "search:\(query)") {
                    try await SearchAPI.search(query: query)
                }
                await self?.finish(results)
            } catch {
                await self?.setLoading(false)  // includes CancellationError
            }
        }
        .bind(to: lifetime)
    }

    private func setLoading(_ value: Bool) { isLoading = value }
    private func finish(_ results: [SearchResult]) {
        self.results = results
        isLoading = false
    }
}
```

### UIKit ViewController with retry

```swift
@MainActor
final class FeedViewController: UIViewController {
    private let lifetime = AsyncLifetime()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        AsyncTask { [weak self] in
            let feed = try await retry(attempts: 3, backoff: .exponential(base: .seconds(1))) {
                try await FeedAPI.fetch()
            }
            await self?.render(feed)
        }
        .bind(to: lifetime)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lifetime.cancelAll()
    }
}
```

### Authenticated networking layer

```swift
actor AuthenticatedAPIClient {

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        // Token refreshed exactly once regardless of concurrent callers
        let token = try await withSingleFlight(key: "auth-token") {
            try await tokenStore.refreshIfNeeded()
        }

        return try await retry(
            attempts: 3,
            backoff: .exponential(base: .milliseconds(500)),
            shouldRetry: { ($0 as? URLError)?.isTransient == true }
        ) {
            try await self.perform(endpoint, authorization: token)
        }
    }
}

private extension URLError {
    var isTransient: Bool {
        [.networkConnectionLost, .timedOut, .notConnectedToInternet].contains(code)
    }
}
```

---

## Architecture

```
┌──────────────────────┐        ┌──────────────────────┐
│    Raw Async Call    │        │   Parallel Requests  │
└──────────┬───────────┘        └──────────┬───────────┘
           │                               │
           ▼                               ▼
┌──────────────────────┐        ┌──────────────────────┐
│  Caller              │        │  SingleFlight        │
│  (any actor or       │        │  Deduplication       │
│   task context)      │        │  (actor-backed)      │
└──────────┬───────────┘        └──────────┬───────────┘
           │                               │
           └───────────────┬───────────────┘
                           ▼
               ┌───────────────────────┐
               │   Scoped Task         │
               │   Management          │
               │                       │
               │   AsyncLifetime       │
               │   AnyCancellable      │
               └───────────┬───────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │   Concurrency         │
               │   Policies            │
               │                       │
               │   retry / backoff     │
               └───────────┬───────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │   AsyncTask           │
               │                       │
               │   Owns Task<Void,Never>│
               │   Enforces strategy   │
               │   declared at site    │
               └───────────┬───────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │   Swift Concurrency   │
               │   Runtime             │
               └────┬────┬────┬────┬───┘
                    │    │    │    │
         ┌──────────┘    │    │    └──────────────┐
         ▼               ▼    ▼                   ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │  Task    │  │ Cancel   │  │ Error    │  │  Debug   │
  │Completion│  │Propagate │  │Propagate │  │Diagnostics│
  └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### Layer responsibilities

| Layer | Responsibility |
|---|---|
| **SingleFlight Registry** | Actor-backed map of `(key, type) → Task`. New callers join rather than duplicate. Waiter-counted: cancelled with its last waiter, cleaned up on completion or failure. |
| **Scoped Task Management** | `AsyncLifetime` — `deinit` cancels. `AnyCancellable` — you control when. |
| **Concurrency Policies** | `retry` — cancellation-aware loop with pluggable `RetryBackoff`. Free functions, not wrapper types. |
| **AsyncTask** | Owns the underlying `Task`. Enforces that every task declares its lifetime strategy. Cancels defensively in `deinit` if strategy was never declared. |
| **Debug Diagnostics** | `os.Logger` events. Gated by `#if DEBUG` + `debugLogging` flag. Zero cost in release. |

---

## Why this approach

### Why `deinit`-based cancellation?

The alternative — manual `cancelAll()` in `deinit` — requires tracking every task as a stored property. It's verbose, error-prone, and routinely forgotten. By attaching cancellation to an `AsyncLifetime` object that shares its owner's lifecycle, cancellation becomes a structural guarantee rather than a coding discipline.

This pattern is directly inspired by Combine's `AnyCancellable`, which proved that lifecycle-bound cancellation is the right default for asynchronous streams. AsyncGuardKit applies the same model to Swift concurrency tasks.

### Why free functions for `withSingleFlight` and `retry`?

Apple uses free functions for coordination primitives: `withTaskGroup`, `withCheckedContinuation`, `withUnsafeContinuation`. This convention signals that the function establishes a scope with well-defined entry and exit semantics. A static method on a facade (`AsyncGuard.singleFlight`) obscures that signal and adds indirection without benefit.

### Why `AnyCancellable` instead of a protocol existential?

Swift cannot make `any Protocol` conform to `Hashable`, which `Set` requires. A concrete wrapper type — identical to Combine's approach — is the correct solution. It also gives stable `ObjectIdentifier`-based identity without requiring conforming types to implement `Hashable` themselves.

### Why not an actor for `AsyncTask`?

Actors serialize access via suspension points. A task wrapper implemented as an actor would add unnecessary awaits to operations that are already thread-safe by construction. `AsyncTask` uses `NSLock` only for its small lifecycle state (ownership, completion hook) — no suspension, no reentrancy risk.

---

## Debug diagnostics

Enable structured logging during development:

```swift
// AppDelegate or @main
#if DEBUG
AsyncGuard.configure(.init(debugLogging: true))
#endif
```

Events appear in **Console.app** and the **Xcode debug console**:

```
[main]       AsyncTask.created
[main]       AsyncTask.boundToLifetime
[background] withSingleFlight.started    key=token-refresh
[background] withSingleFlight.joined     key=token-refresh
[background] withSingleFlight.completed  key=token-refresh
[background] retry.failed  attempt=1  error=URLError(networkConnectionLost)
[background] retry.succeeded  attempt=2
[main]       AsyncLifetime.cancelledAll  count=3
[main]       AsyncLifetime.deallocated
```

All logging is compiled out entirely in release builds — `#if DEBUG` eliminates every call site. Zero runtime cost in production.

---

## Design principles

**Explicit over implicit.** AsyncGuardKit never auto-cancels tasks without declaration or makes scheduling decisions on your behalf. `AsyncTask` operations are `@Sendable` and non-isolated — hop to an actor explicitly (`await self?.apply(...)`). Every behavior is visible at the call site.

**Lifetime binding over manual cleanup.** The `deinit`-based model means correctly managed tasks require zero cleanup code. The absence of a `deinit` override is not a bug — it is the correct outcome.

**Free functions for scoped coordination.** `withSingleFlight` and `retry` follow Apple's `with*` convention, making their scoping semantics immediately recognizable to any Swift developer.

**No dependencies.** Only the Swift standard library, Foundation, and `os.Logger`. Nothing pulled in transitively.

**Testable by design.** Every component exposes what tests need. `SingleFlightRegistry.inFlightCount()` for deduplication assertions. `AsyncLifetime.count` for binding assertions. `retry`'s `shouldRetry` predicate injectable in tests.

---

## License

AsyncGuardKit is available under the MIT license. See [LICENSE](LICENSE) for details.

---

## Contributing

Contributions are welcome. Please read the following before opening a pull request.

**Before contributing:**
- Open an issue to discuss significant changes before implementing
- Check existing issues and pull requests to avoid duplicate work

**Standards:**
- All public API must include full doc comments following the existing style
- All changes must include tests — new behaviour requires new tests, bug fixes require regression tests
- Run `swift test` and ensure all tests pass
- No force unwraps, no global mutable state, no blocking APIs

**Pull request checklist:**
- [ ] Tests added or updated
- [ ] Documentation updated
- [ ] `swift test` passes locally
- [ ] No new compiler warnings

---

<div align="center">
<sub>Built with care for the Swift open-source community.</sub>
</div>
