import SwiftUI

@main
struct FridgeApp: App {
    var body: some Scene {
        WindowGroup { FridgeWebView().ignoresSafeArea().preferredColorScheme(.light) }
    }
}
