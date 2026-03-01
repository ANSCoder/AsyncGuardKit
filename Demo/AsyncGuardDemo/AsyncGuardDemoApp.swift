import SwiftUI
import AsyncGuardKit

@main
struct AsyncGuardDemoApp: App {
    init() {
        #if DEBUG
        AsyncGuard.configure(.init(debugLogging: true))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
