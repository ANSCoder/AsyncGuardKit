import Foundation

// MARK: - AnyCancellable

/// A type-erasing cancellable wrapper for AsyncGuardKit tasks.
///
/// `AnyCancellable` wraps any object with a `cancel()` method into a
/// concrete, `Hashable` type that can be stored in a `Set`. This mirrors
/// Combine's `AnyCancellable` pattern exactly — giving developers the same
/// familiar `.store(in: &cancellables)` API with no Combine dependency.
///
/// You do not create `AnyCancellable` directly. It is produced automatically
/// when you call ``AsyncTask/store(in:)`` on an ``AsyncTask``.
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// AsyncTask { await loadData() }
///     .store(in: &cancellables)
///
/// cancellables.cancelAll()
/// ```
///
/// ## Ownership
///
/// `AnyCancellable` **strongly retains** the wrapped `AsyncTask`. This ensures
/// the task is not deallocated between `.store(in:)` and `cancelAll()`, which
/// would silently prevent cancellation from being delivered.
///
/// ## Identity
///
/// Two `AnyCancellable` instances are equal if and only if they wrap the same
/// underlying object, determined by object identity (`ObjectIdentifier`).
public final class AnyCancellable: Hashable, @unchecked Sendable {

    // MARK: - Storage

    private let _cancel: () -> Void
    private let _id: ObjectIdentifier
    /// Strong reference — keeps the wrapped AsyncTask alive for the
    /// full lifetime of this AnyCancellable. Without this, a task
    /// stored via .store(in:) with no other owner would deallocate
    /// immediately, making cancel() a no-op.
    private let _retained: AnyObject

    // MARK: - Init

    /// Creates a type-erased cancellable wrapping the given object.
    ///
    /// - Parameters:
    ///   - cancellable: The object to retain and identify this cancellable by.
    ///   - cancel: The closure to invoke when ``cancel()`` is called.
    internal init<C: AnyObject>(_ cancellable: C, cancel: @escaping () -> Void) {
        self._cancel = cancel
        self._id = ObjectIdentifier(cancellable)
        self._retained = cancellable
    }

    // MARK: - Public API

    /// Cancels the underlying task.
    ///
    /// Cancellation is cooperative. The underlying work must check
    /// `Task.isCancelled` or call `Task.checkCancellation()` to respond.
    public func cancel() {
        _cancel()
    }

    // MARK: - Hashable

    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool {
        lhs._id == rhs._id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_id)
    }
}

// MARK: - Set<AnyCancellable>

public extension Set where Element == AnyCancellable {

    /// Cancels all tasks in the set and removes them.
    ///
    /// Each element's ``AnyCancellable/cancel()`` is called before the
    /// set is cleared. Safe to call from any thread or actor context.
    ///
    /// ```swift
    /// cancellables.cancelAll()
    /// ```
    mutating func cancelAll() {
        forEach { $0.cancel() }
        removeAll()
    }
}
