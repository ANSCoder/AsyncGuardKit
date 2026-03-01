/// Actor-backed registry that deduplicates concurrent async operations by key.
///
/// `SingleFlightRegistry` maintains a map of in-flight operations keyed by
/// a composite of the caller-supplied key and the expected result type.
/// When a call arrives for a key already in flight, it awaits the existing
/// task rather than starting a new one.
///
/// This type is internal. Public access is via ``withSingleFlight(key:operation:)``.
internal actor SingleFlightRegistry {

    // MARK: - Shared

    static let shared = SingleFlightRegistry()

    // MARK: - Storage

    /// Composite key preventing type collisions across callers sharing the same
    /// string key but expecting different return types.
    private struct FlightKey: Hashable {
        let key: AnyHashable
        let typeID: ObjectIdentifier
    }

    private var flights: [FlightKey: Task<Any, Error>] = [:]

    // MARK: - Execute

    /// Joins an existing flight or starts a new one for the given key and type.
    ///
    /// If a flight for `(key, T)` is already in progress, the caller suspends
    /// and awaits its result. Otherwise a new task is started, recorded, and
    /// awaited. The entry is removed when the task finishes — on success,
    /// failure, or cancellation.
    ///
    /// - Parameters:
    ///   - key: The caller-supplied hashable key.
    ///   - operation: The work to perform if no flight is currently running.
    /// - Returns: The result produced by the in-flight or newly started operation.
    /// - Throws: Rethrows any error from the operation to all waiting callers.
    func execute<Key: Hashable & Sendable, T: Sendable>(
        key: Key,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let flightKey = FlightKey(
            key: AnyHashable(key),
            typeID: ObjectIdentifier(T.self)
        )

        // Join existing flight
        if let existing = flights[flightKey] {
            Diagnostics.log("withSingleFlight.joined", key: String(describing: key))
            let value = try await existing.value
            return value as! T // safe: guaranteed by FlightKey.typeID
        }

        // Start new flight
        Diagnostics.log("withSingleFlight.started", key: String(describing: key))

        let task = Task<Any, Error> {
            try await operation()
        }

        flights[flightKey] = task
        defer {
            flights[flightKey] = nil
            Diagnostics.log("withSingleFlight.completed", key: String(describing: key))
        }

        let value = try await task.value
        return value as! T // safe: guaranteed by FlightKey.typeID
    }

    /// Returns the number of distinct operations currently in flight.
    ///
    /// Intended for diagnostics and tests only.
    func inFlightCount() -> Int {
        flights.count
    }
}
