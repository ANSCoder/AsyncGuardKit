/// An actor-isolated registry that deduplicates concurrent async operations by key.
///
/// `SingleFlightRegistry` is the engine behind ``withSingleFlight(key:operation:)``.
/// It maintains a map of in-flight operations keyed by a composite of the
/// caller-supplied key and the expected result type. When a call arrives for
/// a key already in flight, it joins the existing operation rather than
/// starting a redundant one — all callers suspend and receive the same result.
///
/// ## Type safety
///
/// Each entry in the registry is stored as a `Flight<T>` — a generic,
/// type-preserving box that holds a `Task<T, Error>`. The composite
/// `FlightKey` encodes both the caller's key and `ObjectIdentifier(T.self)`,
/// preventing collisions between callers sharing the same string key but
/// expecting different return types. Joining an existing flight downcasts
/// `AnyFlight → Flight<T>`, which is guaranteed safe by the `typeID` match.
/// No force-unwrapped casts appear at any call site.
///
/// ## Lifecycle
///
/// A flight entry is inserted when the first caller for a given key arrives
/// and removed — via `defer` — when that operation completes, fails, or is
/// cancelled. Subsequent callers for the same key therefore always start a
/// fresh operation rather than joining a stale one.
///
/// ## Thread safety
///
/// All state mutations are actor-isolated. No external synchronization is
/// required. Call sites may be on any actor or unstructured task context.
///
/// - Note: This type is internal. All public access is through
///   ``withSingleFlight(key:operation:)``.
internal actor SingleFlightRegistry {

    static let shared = SingleFlightRegistry()

    // MARK: - Type-preserving flight box

    /// A type-erased protocol that allows heterogeneous storage of `Flight<T>`
    /// values in a single dictionary without losing the ability to await them.
    private protocol AnyFlight: AnyObject {
        /// Awaits the underlying task and returns its value erased to `Any`.
        func awaitResult() async throws -> Any
    }

    /// A concrete, type-preserving wrapper around a `Task<T, Error>`.
    ///
    /// Storing `Task<T, Error>` directly — rather than erasing to `Task<Any, Error>`
    /// — eliminates all force casts at join sites. The `Flight<T>` is recovered
    /// from the registry via `as? Flight<T>`, which is guaranteed to succeed
    /// when `FlightKey.typeID` matches.
    private final class Flight<T: Sendable>: AnyFlight {
        let task: Task<T, Error>
        init(_ task: Task<T, Error>) { self.task = task }
        func awaitResult() async throws -> Any { try await task.value }
    }

    // MARK: - Storage

    /// A composite key that uniquely identifies an in-flight operation by
    /// both its caller-supplied key and its expected return type.
    ///
    /// Including `typeID` prevents a caller expecting `String` from joining
    /// a flight started by a caller expecting `Int` under the same string key.
    private struct FlightKey: Hashable {
        /// The caller-supplied key, type-erased to `AnyHashable`.
        let key: AnyHashable
        /// The `ObjectIdentifier` of the expected return type `T`.
        let typeID: ObjectIdentifier
    }

    private var flights: [FlightKey: AnyFlight] = [:]

    // MARK: - Execute

    /// Joins an existing in-flight operation or starts a new one.
    ///
    /// If an operation for `(key, T)` is already in progress, the caller
    /// suspends and receives its result when it completes. Otherwise a new
    /// `Task<T, Error>` is created, stored under `flightKey`, and awaited.
    /// The entry is removed from the registry when the task finishes —
    /// whether by success, failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: A `Hashable & Sendable` value identifying the operation.
    ///   - operation: The async throwing closure to execute if no flight
    ///     is currently in progress for this key and return type.
    /// - Returns: The value produced by the in-flight or newly started operation,
    ///   shared across all concurrent callers for the same key.
    /// - Throws: Rethrows any error from the operation to all waiting callers.
    func execute<Key: Hashable & Sendable, T: Sendable>(
        key: Key,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let flightKey = FlightKey(
            key: AnyHashable(key),
            typeID: ObjectIdentifier(T.self)
        )

        // Join existing flight — the downcast to Flight<T> is guaranteed safe
        // because FlightKey.typeID encodes T, so only a Flight<T> can be stored
        // under this key. No force cast is required.
        if let existing = flights[flightKey] as? Flight<T> {
            Diagnostics.log("withSingleFlight.joined", key: String(describing: key))
            return try await existing.task.value
        }

        // No flight in progress — start one and register it before suspending
        // so that concurrent callers arriving during the first await join it.
        Diagnostics.log("withSingleFlight.started", key: String(describing: key))

        let task = Task<T, Error> { try await operation() }
        flights[flightKey] = Flight(task)

        defer {
            flights[flightKey] = nil
            Diagnostics.log("withSingleFlight.completed", key: String(describing: key))
        }

        return try await task.value
    }

    /// The number of distinct operations currently in flight.
    ///
    /// Intended for diagnostics and unit tests only. Not part of the public API.
    func inFlightCount() -> Int {
        flights.count
    }
}
