import SwiftUI

@main
struct MaryBottomApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
