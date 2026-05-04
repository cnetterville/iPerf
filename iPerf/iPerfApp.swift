import SwiftUI
import SwiftData

@main
struct iPerfApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TestResult.self)
        .defaultSize(width: 900, height: 650)
    }
}
