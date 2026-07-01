import SwiftUI

struct ServerModeView: View {
    var runner: IperfTestRunner
    @AppStorage("server.port") private var port = 5201

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
                    .frame(maxWidth: 280)
                    .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(runner.isRunning ? .red : .accentColor)

                HStack(spacing: 8) {
                    Circle()
                        .fill(runner.isRunning ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(runner.stateDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !runner.dataPoints.isEmpty {
                    Divider()

                    VStack(spacing: 8) {
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
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .glassEffect(in: .rect(cornerRadius: 16))

                    ThroughputChartView(
                        dataPoints: runner.dataPoints,
                        lineColor: .purple
                    )
                    .padding()
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))

                    HStack(spacing: 0) {
                        statItem(title: "Duration", value: String(format: "%.1fs", runner.elapsedTime), icon: "clock")
                        Divider().frame(height: 44)
                        statItem(title: "Transferred", value: runner.formattedBytes, icon: "arrow.left.arrow.right")
                        Divider().frame(height: 44)
                        statItem(title: "Avg Speed", value: formatSpeed(runner.averageThroughputMbps), icon: "gauge.with.dots.needle.50percent")
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Server Mode")
    }

    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
