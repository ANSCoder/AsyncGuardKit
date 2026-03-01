import Foundation

/// An object that automatically cancels bound tasks when it deallocates.
///
/// `AsyncLifetime` eliminates manual task cancellation by tying task
/// lifetimes to the owning object's lifetime. Declare one as a property,
/// bind tasks to it, and cancellation happens automatically in `deinit`.
///
/// ## Overview
///
/// ```swift
/// class FeedViewModel: ObservableObject {
///     @Published var items: [Item] = []
///     private let lifetime = AsyncLifetime()
///
///     func load() {
///         AsyncTask {
///             let items = try await API.fetchFeed()
///             await MainActor.run { self.items = items }
///         }
///         .bind(to: lifetime)
///         // When FeedViewModel deallocates → task cancelled. Zero cleanup code.
///     }
/// }
/// ```
///
/// ## Multiple tasks
///
/// A single `AsyncLifetime` tracks any number of tasks. All cancel together.
///
/// ```swift
/// func onAppear() {
///     AsyncTask { await loadFeed() }.bind(to: lifetime)
///     AsyncTask { await loadAds() }.bind(to: lifetime)
///     AsyncTask { await prefetchImages() }.bind(to: lifetime)
/// }
/// ```
///
/// ## Manual cancellation
///
/// Call ``cancelAll()`` to cancel all in-flight tasks before deallocation —
/// for example, when the user triggers a refresh.
///
/// ```swift
/// func refresh() {
///     lifetime.cancelAll()
///     AsyncTask { await loadFeed() }.bind(to: lifetime)
/// }
/// ```
///
/// ## Thread safety
///
/// `AsyncLifetime` is thread-safe. Tasks may be added and cancelled
/// concurrently from any thread or actor context.
///
/// - Important: Store `AsyncLifetime` as a `let` property on the owning
///   object (`private let lifetime = AsyncLifetime()`). Premature
///   deallocation cancels all bound tasks immediately.
public final class AsyncLifetime: @unchecked Sendable {

    // MARK: - Storage

    private var _tasks: [ObjectIdentifier: AsyncTask] = [:]
    private let _lock = NSLock()

    // MARK: - Init

    /// Creates a new lifetime scope.
    public init() {}

    deinit {
        cancelAll()
        Diagnostics.log("AsyncLifetime.deallocated")
    }

    // MARK: - Internal

    /// Registers a cancellable with this lifetime.
    ///
    /// Called by ``AsyncTask/bind(to:)``. Not intended for direct use.
    internal func add(_ cancellable: AsyncTask) {
        _lock.withLock {
            _tasks[ObjectIdentifier(cancellable)] = cancellable
        }
        Diagnostics.log("AsyncLifetime.taskAdded", context: "count=\(count)")
    }

    // MARK: - Public API

    /// Cancels all bound tasks and clears the lifetime.
    ///
    /// The lifetime remains valid after this call. New tasks can be bound
    /// and will be tracked normally.
    ///
    /// ```swift
    /// func refresh() {
    ///     lifetime.cancelAll()
    ///     AsyncTask { await reload() }.bind(to: lifetime)
    /// }
    /// ```
    public func cancelAll() {
        let snapshot = _lock.withLock {
            let current = _tasks
            _tasks.removeAll()
            return current
        }
        snapshot.values.forEach { $0.cancel() }
        Diagnostics.log("AsyncLifetime.cancelledAll", context: "count=\(snapshot.count)")
    }

    /// The number of tasks currently bound to this lifetime.
    ///
    /// Intended for diagnostics and testing.
    public var count: Int {
        _lock.withLock { _tasks.count }
    }
}
