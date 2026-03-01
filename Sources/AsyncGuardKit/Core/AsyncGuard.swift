/// The primary entry point for configuring AsyncGuardKit.
///
/// `AsyncGuard` provides a process-wide configuration surface for
/// enabling diagnostics and runtime behavior customization.
///
/// This type is intentionally minimal. It exposes only configuration
/// and coordination APIs that apply globally across the process.
///
/// ## Overview
///
/// Most AsyncGuardKit APIs are free functions (`retry`, `withSingleFlight`)
/// or lifetime-bound constructs (`AsyncTask`, `AsyncLifetime`).
///
/// `AsyncGuard` exists to provide:
///
/// - Process-wide configuration
/// - Debug logging control
/// - Future extensibility for global coordination behavior
///
/// Configuration is optional. If you do not call `configure(_:)`,
/// AsyncGuardKit operates with safe default values.
///
/// ## Usage
///
/// Call `configure(_:)` once during application startup:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         #if DEBUG
///         AsyncGuard.configure(.init(debugLogging: true))
///         #endif
///     }
/// }
/// ```
///
/// Configuration is typically limited to debug builds.
/// Runtime overhead is negligible in release builds.
///
/// - Important: Configuration should be set only once at launch.
///   Changing configuration at runtime is not recommended.
public enum AsyncGuard {

    /// Applies process-wide configuration to AsyncGuardKit.
    ///
    /// This method updates the shared configuration store used
    /// internally by AsyncGuardKit components such as diagnostics
    /// and debug validation.
    ///
    /// If called multiple times, the most recent configuration
    /// replaces the previous one.
    ///
    /// In release builds, debug-only settings have no effect.
    ///
    /// - Parameter configuration: The configuration to apply.
    public static func configure(_ configuration: AsyncGuardConfiguration) {
        ConfigurationStore.shared.set(configuration)
        Diagnostics.log("AsyncGuard.configured", context: "debugLogging=\(configuration.debugLogging)")
    }
}
