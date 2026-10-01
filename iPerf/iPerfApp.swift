import SwiftUI
import SwiftData

@main
struct iPerfApp: App {
    @State private var testRunner = IperfTestRunner()
    @State private var serverRunner = IperfTestRunner()
    @AppStorage(ClientPrefs.hideDockIcon) private var hideDockIcon = false

    private var serverActive: Bool {
        serverRunner.isRunning && serverRunner.isServerMode
    }

    private var menuBarVisible: Bool {
        hideDockIcon || serverActive
    }

    private var menuBarSpeed: String? {
        guard serverActive, serverRunner.currentThroughputMbps > 0 else { return nil }
        return "\(serverRunner.formattedCurrentSpeed) \(serverRunner.speedUnit)"
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
        .commands {
            TestCommands(runner: testRunner)
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: Binding(
            get: { menuBarVisible },
            set: { _ in }
        )) {
            ServerMenuContent(runner: serverRunner, hideDockIcon: $hideDockIcon)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                if let menuBarSpeed {
                    Text(menuBarSpeed)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct TestCommands: Commands {
    var runner: IperfTestRunner
    @FocusedValue(\.deleteResultAction) private var deleteResult

    var body: some Commands {
        CommandMenu("Test") {
            Button(runner.isRunning ? "Stop Test" : "Start Test") {
                if runner.isRunning {
                    runner.stop()
                    return
                }
                let profile = TestProfile.current
                if profile.isValid {
                    runner.start(profile: profile)
                } else {
                    NSSound.beep()
                }
            }
            .keyboardShortcut("r")

            Divider()

            Button("Delete Result") {
                // ⌘⌫ also means "delete to line start" while editing text; keep that behavior.
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                } else {
                    deleteResult?()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(deleteResult == nil)
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
            if let client = runner.connectedClient {
                Text("Client: \(client)")
                Text("\(runner.formattedCurrentSpeed) \(runner.speedUnit)")
            }
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
