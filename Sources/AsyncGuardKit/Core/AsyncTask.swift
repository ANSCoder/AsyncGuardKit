import Foundation

/// A unit of asynchronous work with an explicit, manageable lifetime.
///
/// `AsyncTask` wraps a Swift `Task` and adds lifetime-binding semantics
/// that eliminate manual cancellation in the common case. Every `AsyncTask`
/// requires an explicit lifetime declaration at the call site — preventing
/// the silent task leaks that cause crashes and stale state mutations.
///
/// ## Lifetime strategies
///
/// Choose one of three strategies when creating a task:
///
/// **Bind to object lifetime (recommended default)**
/// ```swift
/// AsyncTask { await loadFeed() }
///     .bind(to: lifetime)
/// // Cancelled automatically when the owning object deallocates.
/// ```
///
/// **Store in a cancellable set (manual control)**
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// AsyncTask { await loadFeed() }
///     .store(in: &cancellables)
/// // You control when cancellables.cancelAll() is called.
/// ```
///
/// **Detached (explicit fire-and-forget)**
/// ```swift
/// AsyncTask { await Analytics.log(.viewAppeared) }
///     .detached()
/// // Runs to completion. No lifetime management.
/// ```
///
/// ## Threading
///
/// `AsyncTask` does not alter the execution context of the provided closure.
/// The closure executes on the actor context it was defined in. Use
/// `await MainActor.run { }` or `@MainActor` annotations directly when
/// main-thread execution is required.
///
/// ## Cancellation
///
/// Cancellation is cooperative. Long-running work should check
/// `Task.isCancelled` or call `try Task.checkCancellation()` at
/// natural suspension points.
public final class AsyncTask: @unchecked Sendable {

    // MARK: - Storage

    private let _task: Task<Void, Never>
    private var _ownershipTransferred = false

    // MARK: - Init

    /// Creates a task that executes the provided async operation.
    ///
    /// The task begins executing immediately. You must follow the call
    /// with `.bind(to:)`, `.store(in:)`, or `.detached()` to declare
    /// the intended lifetime strategy.
    ///
    /// - Parameters:
    ///   - priority: Task priority. Defaults to `nil` (inherits caller's priority).
    ///   - operation: The asynchronous work to perform.
    public init(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        _task = Task(priority: priority) {
            await operation()
        }
        Diagnostics.log("AsyncTask.created")
    }

    /// Creates a task that executes the provided throwing async operation.
    ///
    /// Errors thrown by the operation are silently discarded at the task
    /// boundary. Handle errors within the closure when observation is needed.
    ///
    /// - Parameters:
    ///   - priority: Task priority. Defaults to `nil` (inherits caller's priority).
    ///   - operation: The asynchronous, throwing work to perform.
    public init(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        _task = Task(priority: priority) {
            do {
                try await operation()
            } catch is CancellationError {
                Diagnostics.log("AsyncTask.cancelled")
            } catch {
                Diagnostics.log("AsyncTask.failed", context: String(describing: error))
            }
        }
        Diagnostics.log("AsyncTask.created")
    }

    deinit {
        if !_ownershipTransferred {
            _task.cancel()
            Diagnostics.log("AsyncTask.cancelledOnDeinit")
        }
    }

    // MARK: - Lifetime Strategies

    /// Binds this task to an ``AsyncLifetime``.
    ///
    /// The task is cancelled automatically when the lifetime deallocates.
    /// This is the recommended strategy for ViewModels and services.
    ///
    /// ```swift
    /// AsyncTask { await fetchProfile() }
    ///     .bind(to: lifetime)
    /// ```
    ///
    /// - Parameter lifetime: The lifetime to bind to.
    @discardableResult
    public func bind(to lifetime: AsyncLifetime) -> Self {
        _ownershipTransferred = true
        lifetime.add(self)
        Diagnostics.log("AsyncTask.boundToLifetime")
        return self
    }

    /// Stores this task in an ``AnyCancellable`` set.
    ///
    /// Wraps the task in an ``AnyCancellable`` and inserts it into the set.
    /// The task is cancelled when ``Set/cancelAll()`` is called or the set
    /// is deallocated.
    ///
    /// ```swift
    /// var cancellables = Set<AnyCancellable>()
    ///
    /// AsyncTask { await fetchFeed() }
    ///     .store(in: &cancellables)
    /// ```
    ///
    /// - Parameter set: The ``AnyCancellable`` set to store into.
    @discardableResult
    public func store(in set: inout Set<AnyCancellable>) -> Self {
        _ownershipTransferred = true
        let cancellable = AnyCancellable(self) { [weak self] in
            self?._task.cancel()
        }
        set.insert(cancellable)
        Diagnostics.log("AsyncTask.storedInSet")
        return self
    }

    /// Explicitly opts out of lifetime management.
    ///
    /// The task runs to completion regardless of any surrounding scope.
    /// Use sparingly — prefer ``bind(to:)`` in most cases.
    ///
    /// ```swift
    /// AsyncTask { await Analytics.log(.screenViewed) }
    ///     .detached()
    /// ```
    @discardableResult
    public func detached() -> Self {
        _ownershipTransferred = true
        Diagnostics.log("AsyncTask.detached")
        return self
    }

    /// Cancels the underlying task cooperatively.
    public func cancel() {
        _task.cancel()
        Diagnostics.log("AsyncTask.cancelled")
    }
}
