import Foundation

/// Process-wide configuration for AsyncGuardKit runtime behavior.
///
/// Use `AsyncGuardConfiguration` to control debug logging and runtime
/// diagnostics. Apply it once at app startup via ``AsyncGuard/configure(_:)``.
///
/// All debug-only settings are stripped entirely in release builds and
/// carry zero runtime cost in production.
///
/// ```swift
/// // In AppDelegate or @main
/// #if DEBUG
/// AsyncGuard.configure(.init(debugLogging: true))
/// #endif
/// ```
///
/// - Note: Configuration is process-wide. Updating it mid-flight is safe
///   but existing in-flight operations may observe the previous value.
public struct AsyncGuardConfiguration: Sendable {

    /// Enables verbose debug logging via `os.Logger`.
    ///
    /// When `true`, AsyncGuardKit emits structured log entries for task
    /// lifecycle events, single-flight coalescing, and retry attempts.
    /// Has no effect in release builds.
    ///
    /// Default: `false`
    public var debugLogging: Bool

    /// Creates a configuration instance.
    ///
    /// - Parameter debugLogging: Enables debug logging in debug builds only.
    ///   Defaults to `false`.
    public init(debugLogging: Bool = false) {
        self.debugLogging = debugLogging
    }

    /// The default configuration. Debug logging disabled.
    public static let `default` = AsyncGuardConfiguration()
}

// MARK: - Internal Store

/// Thread-safe store for the active AsyncGuardConfiguration.
internal final class ConfigurationStore: @unchecked Sendable {

    static let shared = ConfigurationStore()

    private let lock = NSLock()
    private var _configuration: AsyncGuardConfiguration = .default

    private init() {}

    func set(_ configuration: AsyncGuardConfiguration) {
        lock.withLock { _configuration = configuration }
    }

    func get() -> AsyncGuardConfiguration {
        lock.withLock { _configuration }
    }
}

// MARK: - NSLock convenience

extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
