import SwiftUI
import SwiftData

@main
struct iPerfApp: App {
    @State private var testRunner = IperfTestRunner()
    @State private var serverRunner = IperfTestRunner()
    @AppStorage("hideDockIcon") private var hideDockIcon = false

    private var menuBarVisible: Bool {
        hideDockIcon || (serverRunner.isRunning && serverRunner.isServerMode)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(testRunner: testRunner, serverRunner: serverRunner)
                .onAppear {
                    if hideDockIcon {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
        .modelContainer(for: TestResult.self)
        .defaultSize(width: 900, height: 650)

        MenuBarExtra(isInserted: Binding(
            get: { menuBarVisible },
            set: { _ in }
        )) {
            ServerMenuContent(runner: serverRunner, hideDockIcon: $hideDockIcon)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}

struct ServerMenuContent: View {
    var runner: IperfTestRunner
    @Binding var hideDockIcon: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if runner.isRunning && runner.isServerMode {
            Text("Server Running — Port \(runner.serverPort, format: .number.grouping(.never))")
            Divider()
            Button("Stop Server") {
                runner.stop()
            }
        } else {
            Text("Server Stopped")
            Divider()
            Button("Start Server (Port \(runner.serverPort, format: .number.grouping(.never)))") {
                runner.startServer(port: runner.serverPort)
            }
        }
        Divider()
        Button("Open iPerf") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Toggle("Hide Dock Icon", isOn: $hideDockIcon)
            .onChange(of: hideDockIcon) { _, newValue in
                NSApp.setActivationPolicy(newValue ? .accessory : .regular)
            }
        Divider()
        Button("Quit iPerf") {
            runner.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
