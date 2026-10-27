import Foundation

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
/// to `Flight<T>`, which is guaranteed safe by the `typeID` match.
/// No force-unwrapped casts appear at any call site.
///
/// ## Lifecycle
///
/// A flight entry is inserted when the first caller for a given key arrives
/// and removed once every waiter has left — because the operation completed,
/// failed, or all waiters were cancelled. Cancelling one waiter never cancels
/// the shared operation while others still wait; cancelling the last one does,
/// and the entry is dropped immediately so the next caller starts fresh.
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

    private final class Flight<T: Sendable> {
        let id = UUID()
        let task: Task<T, Error>
        var waiters: Set<UUID> = []
        init(_ task: Task<T, Error>) { self.task = task }
    }

    // MARK: - Storage

    // AnyHashable only ever wraps a `Key: Sendable` (see `execute`).
    private struct FlightKey: Hashable, @unchecked Sendable {
        let key: AnyHashable
        let typeID: ObjectIdentifier
    }

    /// Type-erased view of a flight's waiter bookkeeping.
    private struct Entry {
        let id: UUID
        let box: AnyObject
        let cancel: () -> Void
        let removeWaiter: (UUID) -> Bool   // true when no waiters remain
    }

    private var flights: [FlightKey: Entry] = [:]

    // MARK: - Execute

    func execute<Key: Hashable & Sendable, T: Sendable>(
        key: Key,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let flightKey = FlightKey(
            key: AnyHashable(key),
            typeID: ObjectIdentifier(T.self)
        )

        // The downcast is guaranteed safe because FlightKey.typeID encodes T.
        let flight: Flight<T>
        if let existing = flights[flightKey]?.box as? Flight<T> {
            Diagnostics.log("withSingleFlight.joined", key: String(describing: key))
            flight = existing
        } else {
            // Register before suspending so concurrent callers join this flight.
            Diagnostics.log("withSingleFlight.started", key: String(describing: key))
            let new = Flight<T>(Task { try await operation() })
            flights[flightKey] = Entry(
                id: new.id,
                box: new,
                cancel: { new.task.cancel() },
                removeWaiter: { new.waiters.remove($0); return new.waiters.isEmpty }
            )
            flight = new
        }

        let waiterID = UUID()
        flight.waiters.insert(waiterID)
        defer {
            release(flightKey, flightID: flight.id, waiter: waiterID)
            Diagnostics.log("withSingleFlight.completed", key: String(describing: key))
        }

        let task = flight.task
        let flightID = flight.id
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            // Caller cancelled: leave the flight, cancelling the work if nobody is left.
            Task { await self.release(flightKey, flightID: flightID, waiter: waiterID) }
        }
    }

    /// Removes `waiter`; when the last one leaves, cancels the work and drops the entry.
    /// Idempotent, and a no-op if the key now belongs to a newer flight.
    private func release(_ key: FlightKey, flightID: UUID, waiter: UUID) {
        guard let entry = flights[key], entry.id == flightID else { return }
        guard entry.removeWaiter(waiter) else { return }
        entry.cancel()
        flights[key] = nil
    }

    func inFlightCount() -> Int {
        flights.count
    }
}
