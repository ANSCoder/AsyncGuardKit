/// Executes an operation exactly once for a given key, coalescing all
/// concurrent callers until the operation completes.
///
/// `withSingleFlight` prevents redundant concurrent executions of the same
/// logical operation. When multiple callers invoke `withSingleFlight` with
/// the same key simultaneously, only one underlying operation executes.
/// All callers suspend and receive the same result — or error — on completion.
///
/// ## Overview
///
/// The canonical use case is token refresh. Without deduplication, ten
/// concurrent API calls each detecting an expired token will each trigger
/// their own refresh — hammering your auth server and often producing
/// race conditions. With `withSingleFlight`, one refresh runs and all
/// ten callers receive the result:
///
/// ```swift
/// func fetchWithAuth() async throws -> Data {
///     let token = try await withSingleFlight(key: "token-refresh") {
///         try await authClient.refreshAccessToken()
///     }
///     return try await api.fetch(authorization: token)
/// }
/// ```
///
/// ## Typed keys
///
/// Keys are typed and `Hashable`. Use enums for large systems to prevent
/// accidental key collisions at compile time:
///
/// ```swift
/// enum FlightKey: Hashable {
///     case tokenRefresh
///     case userProfile(id: String)
///     case feedPage(cursor: String)
/// }
///
/// let token = try await withSingleFlight(key: FlightKey.tokenRefresh) { ... }
/// ```
///
/// ## Error propagation
///
/// If the operation throws, all waiting callers receive the same error.
/// The registry entry is removed so the next call starts a fresh operation.
///
/// ## Threading
///
/// Safe to call from any actor context. The registry is actor-isolated
/// internally and requires no external synchronization.
///
/// ## When not to use
///
/// Do not use for operations where each caller needs an independent result,
/// or where repeated execution for the same key is intentional.
///
/// - Parameters:
///   - key: A `Hashable` value identifying the operation. Concurrent calls
///     with equal keys are coalesced into a single execution.
///   - operation: The async, throwing operation to deduplicate.
/// - Returns: The result shared by all concurrent callers for this key.
/// - Throws: Rethrows any error from the operation, propagated to all waiters.
public func withSingleFlight<Key: Hashable & Sendable, T: Sendable>(
    key: Key,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    Diagnostics.log("withSingleFlight.called", key: String(describing: key))
    return try await SingleFlightRegistry.shared.execute(key: key, operation: operation)
}
