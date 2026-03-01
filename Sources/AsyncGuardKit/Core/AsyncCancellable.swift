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
/// // Cancel everything at once
/// cancellables.cancelAll()
/// ```
///
/// ## Identity
///
/// Two `AnyCancellable` instances are equal if and only if they wrap the
/// same underlying object. This is determined by object identity (`===`),
/// not by value equality.
///
/// - Note: `AnyCancellable` is `Hashable` via `ObjectIdentifier`, making
///   it safe to store in `Set` and use as a `Dictionary` key.
public final class AnyCancellable: Hashable, @unchecked Sendable {

    private let _cancel: () -> Void
    private let _id: ObjectIdentifier

    /// Creates a type-erased cancellable wrapping the given object.
    ///
    /// - Parameter cancellable: Any object that conforms to the internal
    ///   cancellation contract. Typically an ``AsyncTask``.
    internal init<C: AnyObject>(_ cancellable: C, cancel: @escaping () -> Void) {
        self._cancel = cancel
        self._id = ObjectIdentifier(cancellable)
    }

    /// Cancels the underlying task.
    ///
    /// Cancellation is cooperative. The underlying work must check
    /// `Task.isCancelled` or call `Task.checkCancellation()` to respond.
    public func cancel() {
        _cancel()
    }

    // MARK: Hashable

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
