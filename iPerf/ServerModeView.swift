import SwiftUI

struct ServerModeView: View {
    var runner: IperfTestRunner
    @State private var port = 5201

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $port, format: .number)
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

                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text(runner.formattedBytes)
                                .font(.headline.monospacedDigit())
                            Text("Transferred")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Text(String(format: "%.1fs", runner.elapsedTime))
                                .font(.headline.monospacedDigit())
                            Text("Duration")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Server Mode")
    }
}
