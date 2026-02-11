import SwiftUI

@main
struct AmbientApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(self.appModel)
        }
    }
}
