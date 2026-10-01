import SwiftUI

struct ServerModeView: View {
    var runner: IperfTestRunner
    @AppStorage(ClientPrefs.serverPort) private var port = 5201

    @State private var addresses: [LocalAddress] = []
    @State private var copiedID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                .disabled(runner.isRunning)

                Button {
                    if runner.isRunning {
                        runner.stop()
                    } else {
                        runner.startServer(port: port)
                    }
                } label: {
                    Label(
                        runner.isRunning ? "Stop Server" : "Start Server",
                        systemImage: runner.isRunning ? "stop.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(width: 200)
                    .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .tint(runner.isRunning ? .red : .accentColor)
                .disabled(!runner.isRunning && !(1...65535).contains(port))

                statusRow

                addressCard

                if !runner.dataPoints.isEmpty {
                    Divider()

                    speedDisplay

                    ThroughputChartView(
                        dataPoints: runner.dataPoints,
                        lineColor: .purple
                    )
                    .cardStyle()

                    StatRow {
                        StatTile(title: "Elapsed", value: String(format: "%.1fs", runner.elapsedTime), icon: "clock")
                        Divider().frame(height: 44)
                        StatTile(title: "Transferred", value: runner.formattedBytes, icon: "arrow.left.arrow.right")
                        Divider().frame(height: 44)
                        StatTile(title: "Avg Speed", value: formatSpeed(runner.averageThroughputMbps), icon: "gauge.with.dots.needle.50percent")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Server Mode")
        .onAppear { refreshAddresses() }
        .onChange(of: runner.isRunning) { refreshAddresses() }
    }

    // MARK: - Sections

    private var statusRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(runner.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(runner.stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let client = runner.connectedClient {
                Label("Connected client: \(client)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connect to this Mac")
                    .font(.headline)
                Spacer()
                Button {
                    refreshAddresses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh addresses")
            }

            if addresses.isEmpty {
                Text("No network connection found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(addresses) { item in
                        GridRow {
                            Text(item.interface)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.address)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            copyButton(
                                id: item.id + "-addr",
                                text: item.address,
                                label: "Copy address"
                            )
                            copyButton(
                                id: item.id + "-cmd",
                                text: command(for: item.address),
                                label: "Copy iperf3 command",
                                symbol: "terminal"
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var speedDisplay: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(runner.formattedCurrentSpeed)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(runner.speedUnit)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .animation(.easeInOut(duration: 0.3), value: runner.currentThroughputMbps)
        .padding(.vertical, 16)
        .heroStyle()
    }

    // MARK: - Helpers

    private func copyButton(id: String, text: String, label: String, symbol: String = "doc.on.doc") -> some View {
        Button {
            copy(text, id: id)
        } label: {
            Image(systemName: copiedID == id ? "checkmark" : symbol)
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .help(label)
    }

    private func command(for address: String) -> String {
        port == 5201 ? "iperf3 -c \(address)" : "iperf3 -c \(address) -p \(port)"
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == id { copiedID = nil }
        }
    }

    private func refreshAddresses() {
        addresses = NetworkInfo.localAddresses()
    }
}
