import SwiftUI
import SwiftData

struct SpeedTestView: View {
    var runner: IperfTestRunner
    @Environment(\.modelContext) private var modelContext

    @State private var serverAddress = "192.168.1.1"
    @State private var port = 5201
    @State private var selectedProtocol = "TCP"
    @State private var selectedDirection = "Download"
    @State private var streamCount = 3
    @State private var duration: Double = 10
    @State private var showingError = false
    @Query(sort: \TestResult.date, order: .reverse) private var testResults: [TestResult]

    private var previousAddresses: [String] {
        var seen = Set<String>()
        return testResults.compactMap { result in
            let addr = result.serverAddress
            guard !addr.isEmpty, !seen.contains(addr) else { return nil }
            seen.insert(addr)
            return addr
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                configurationCard
                    .disabled(runner.isRunning)

                actionButton

                if runner.isRunning || !runner.dataPoints.isEmpty {
                    Divider()
                    resultsSection
                }
            }
            .padding(24)
        }
        .navigationTitle("Speed Test")
        .onChange(of: runner.isRunning) { wasRunning, isNowRunning in
            if wasRunning && !isNowRunning && runner.stateDescription == "Completed" && !runner.isServerMode {
                saveResult()
            }
        }
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(runner.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: runner.stateDescription) { _, newValue in
            if newValue == "Error" && runner.errorMessage != nil {
                showingError = true
            }
        }
    }

    // MARK: - Configuration

    private var configurationCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("hostname or IP", text: $serverAddress)
                            .textFieldStyle(.roundedBorder)
                        if !previousAddresses.isEmpty {
                            Menu {
                                ForEach(previousAddresses, id: \.self) { address in
                                    Button(address) {
                                        serverAddress = address
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("port", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protocol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Protocol", selection: $selectedProtocol) {
                        Text("TCP").tag("TCP")
                        Text("UDP").tag("UDP")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Direction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Direction", selection: $selectedDirection) {
                        Label("Download", systemImage: "arrow.down").tag("Download")
                        Label("Upload", systemImage: "arrow.up").tag("Upload")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parallel Streams")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("\(streamCount)", value: $streamCount, in: 1...64)
                        .frame(width: 140)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("\(Int(duration))s", value: $duration, in: 1...300, step: 5)
                        .frame(width: 140)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            if runner.isRunning {
                runner.stop()
            } else {
                startTest()
            }
        } label: {
            Label(
                runner.isRunning ? "Stop Test" : "Start Test",
                systemImage: runner.isRunning ? "stop.fill" : "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: 280)
            .padding(.vertical, 4)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(runner.isRunning ? .red : .accentColor)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 20) {
            speedDisplay

            ThroughputChartView(
                dataPoints: runner.dataPoints,
                lineColor: selectedDirection == "Download" ? .blue : .green
            )
            .padding()
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))

            statsGrid
        }
    }

    private var speedDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedDirection == "Download" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(selectedDirection == "Download" ? .blue : .green)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(runner.formattedCurrentSpeed)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(runner.speedUnit)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeInOut(duration: 0.3), value: runner.currentThroughputMbps)

            HStack(spacing: 8) {
                Text(runner.stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(runner.isRunning ? .primary : .secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(selectedProtocol) · \(streamCount) stream\(streamCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statItem(title: "Duration", value: String(format: "%.1fs", runner.elapsedTime), icon: "clock")
            Divider().frame(height: 44)
            statItem(title: "Transferred", value: runner.formattedBytes, icon: "arrow.left.arrow.right")
            if selectedProtocol == "UDP" {
                Divider().frame(height: 44)
                statItem(title: "Jitter", value: String(format: "%.2f ms", runner.lastJitter), icon: "waveform.path")
                Divider().frame(height: 44)
                statItem(title: "Loss", value: String(format: "%.1f%%", runner.packetLossPercent), icon: "exclamationmark.triangle")
            } else {
                Divider().frame(height: 44)
                statItem(title: "RTT", value: String(format: "%.1f ms", runner.lastRtt), icon: "arrow.left.arrow.right.circle")
                Divider().frame(height: 44)
                statItem(title: "Avg Speed", value: formatSpeed(runner.averageThroughputMbps), icon: "gauge.with.dots.needle.50percent")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
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

    // MARK: - Actions

    private func startTest() {
        runner.startClient(
            address: serverAddress,
            port: port,
            protocolType: selectedProtocol,
            direction: selectedDirection,
            streams: streamCount,
            duration: duration
        )
    }

    private func saveResult() {
        let result = TestResult(
            serverAddress: serverAddress,
            port: port,
            protocolName: selectedProtocol,
            direction: selectedDirection,
            streamCount: streamCount,
            testDuration: duration
        )
        result.averageThroughputMbps = runner.averageThroughputMbps
        result.maxThroughputMbps = runner.maxThroughputMbps
        result.totalBytes = runner.totalBytesTransferred
        result.jitter = runner.lastJitter
        result.packetLossPercent = runner.packetLossPercent
        result.rttMs = runner.lastRtt
        result.dataPoints = runner.dataPoints
        result.status = "completed"
        modelContext.insert(result)
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.1f Gbps", mbps / 1000)
        }
        return String(format: "%.1f Mbps", mbps)
    }
}
