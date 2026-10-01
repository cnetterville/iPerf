import SwiftUI

struct SettingsView: View {
    @AppStorage(ClientPrefs.hideDockIcon) private var hideDockIcon = false
    @AppStorage(ClientPrefs.notifyOnCompletion) private var notifyOnCompletion = false

    @AppStorage(ClientPrefs.transport) private var selectedProtocol = TestProfile.defaults.transport
    @AppStorage(ClientPrefs.direction) private var selectedDirection = TestProfile.defaults.direction
    @AppStorage(ClientPrefs.streamCount) private var streamCount = TestProfile.defaults.streams
    @AppStorage(ClientPrefs.duration) private var duration = TestProfile.defaults.duration
    @AppStorage(ClientPrefs.serverPort) private var serverPort = 5201

    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }

                Toggle("Notify when a test completes", isOn: $notifyOnCompletion)
                    .onChange(of: notifyOnCompletion) { _, enabled in
                        guard enabled else { return }
                        Task {
                            let granted = await NotificationManager.requestAuthorization()
                            if !granted {
                                notifyOnCompletion = false
                                notificationsDenied = true
                            }
                        }
                    }
                if notificationsDenied {
                    Text("Notifications are disabled for iPerf in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Client Defaults") {
                Picker("Protocol", selection: $selectedProtocol) {
                    ForEach(TransportProtocol.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Direction", selection: $selectedDirection) {
                    ForEach(TestDirection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Stepper("Parallel streams: \(streamCount)", value: $streamCount, in: 1...64)
                Stepper("Duration: \(Int(duration))s", value: $duration, in: 5...300, step: 5)
            }

            Section("Server Defaults") {
                TextField("Listen port", value: $serverPort, format: .number.grouping(.never))
                    .frame(maxWidth: 200)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
