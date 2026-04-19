import SwiftUI

@main
struct TinIAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 760)
        #endif
    }
}
