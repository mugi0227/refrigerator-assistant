import SwiftUI

@main
struct FridgeApp: App {
    var body: some Scene {
        WindowGroup {
            FridgeWebView()
                .background(Color(red: 0.969, green: 0.973, blue: 0.949).ignoresSafeArea())
                .preferredColorScheme(.light)
        }
    }
}
