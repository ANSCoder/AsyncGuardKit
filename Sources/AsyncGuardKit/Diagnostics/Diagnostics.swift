import Foundation
import os

/// Internal diagnostics logger for AsyncGuardKit.
///
/// All logging is gated behind `#if DEBUG` and the active
/// ``AsyncGuardConfiguration/debugLogging`` flag. In release builds,
/// the compiler eliminates every call site entirely — zero cost.
///
/// Use ``Diagnostics/log(_:key:context:)`` at internal operation boundaries
/// to emit structured log entries visible in Console.app and Xcode's
/// debug console.
internal enum Diagnostics {

    private static let logger = Logger(
        subsystem: "com.asyncguardkit",
        category: "AsyncGuardKit"
    )

    /// Emits a structured debug log entry.
    ///
    /// No-op in release builds. No-op when `debugLogging` is `false`.
    ///
    /// - Parameters:
    ///   - event: A short description of the event (e.g. `"singleFlight.joined"`).
    ///   - key: Optional task or flight key for correlation.
    ///   - context: Optional freeform context string.
    static func log(
        _ event: String,
        key: String? = nil,
        context: String? = nil
    ) {
#if DEBUG
        guard ConfigurationStore.shared.get().debugLogging else { return }

        let keyInfo = key.map { " key=\($0)" } ?? ""
        let contextInfo = context.map { " context=\($0)" } ?? ""
        let thread = Thread.isMainThread ? "main" : "background"

        logger.debug("[\(thread)] \(event)\(keyInfo)\(contextInfo)")
#endif
    }
}
