import SwiftUI
import SwiftData

@main
struct iPerfApp: App {
    @State private var testRunner = IperfTestRunner()
    @State private var serverRunner = IperfTestRunner()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(testRunner: testRunner, serverRunner: serverRunner)
        }
        .modelContainer(for: TestResult.self)
        .defaultSize(width: 900, height: 650)

        MenuBarExtra(isInserted: Binding(
            get: { serverRunner.isRunning && serverRunner.isServerMode },
            set: { _ in }
        )) {
            ServerMenuContent(runner: serverRunner)
        } label: {
            Image(systemName: "network")
        }
    }
}

struct ServerMenuContent: View {
    var runner: IperfTestRunner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if runner.isRunning && runner.isServerMode {
            Text("Server Running — Port \(runner.serverPort)")
            Divider()
            Button("Stop Server") {
                runner.stop()
            }
        } else {
            Text("Server Stopped")
            Divider()
            Button("Start Server (Port \(runner.serverPort))") {
                runner.startServer(port: runner.serverPort)
            }
        }
        Divider()
        Button("Open iPerf") {
            openWindow(id: "main")
        }
        Divider()
        Button("Quit iPerf") {
            runner.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
