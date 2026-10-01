import SwiftUI
import SwiftData

struct SpeedTestView: View {
    var runner: IperfTestRunner
    @Environment(\.modelContext) private var modelContext

    @AppStorage("client.serverAddress") private var serverAddress = "192.168.1.1"
    @AppStorage("client.port") private var port = 5201
    @AppStorage("client.protocol") private var selectedProtocol = TransportProtocol.tcp
    @AppStorage("client.direction") private var selectedDirection = TestDirection.download
    @AppStorage("client.streamCount") private var streamCount = 3
    @AppStorage("client.duration") private var duration: Double = 10
    @AppStorage("client.bandwidthLimit") private var bandwidthLimit: Double = 1
    @AppStorage("client.bandwidthUnit") private var bandwidthUnit = "Mbps"
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
            if wasRunning && !isNowRunning && runner.state == .completed && !runner.isServerMode {
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
                        ForEach(TransportProtocol.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Direction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Direction", selection: $selectedDirection) {
                        Label("Download", systemImage: "arrow.down").tag(TestDirection.download)
                        Label("Upload", systemImage: "arrow.up").tag(TestDirection.upload)
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

            if selectedProtocol == .udp {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bandwidth Limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("Rate", value: $bandwidthLimit, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Picker("Unit", selection: $bandwidthUnit) {
                                Text("Mbps").tag("Mbps")
                                Text("Gbps").tag("Gbps")
                            }
                            .labelsHidden()
                            .frame(width: 80)
                        }
                    }
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
        .disabled(!runner.isRunning && !isInputValid)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 20) {
            speedDisplay

            ThroughputChartView(
                dataPoints: runner.dataPoints,
                lineColor: selectedDirection.color
            )
            .padding()
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))

            statsGrid
        }
    }

    private var speedDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedDirection.symbol)
                .font(.system(size: 28))
                .foregroundStyle(selectedDirection.color)

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
                Text("\(selectedProtocol.rawValue) · \(streamCount) stream\(streamCount == 1 ? "" : "s")")
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
            if selectedProtocol == .udp {
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

    private var isInputValid: Bool {
        !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...65535).contains(port)
            && (selectedProtocol == .tcp || (bandwidthLimit.isFinite && bandwidthLimit > 0))
    }

    private var bandwidthBitsPerSecond: UInt64 {
        let mbps = bandwidthUnit == "Gbps" ? bandwidthLimit * 1000 : bandwidthLimit
        let bps = mbps * 1_000_000
        guard bps.isFinite, bps > 0 else { return 0 }
        return UInt64(min(bps, Double(UInt64.max / 2)))
    }

    private func startTest() {
        runner.startClient(
            address: serverAddress.trimmingCharacters(in: .whitespaces),
            port: port,
            protocolType: selectedProtocol,
            direction: selectedDirection,
            streams: streamCount,
            duration: duration,
            rate: selectedProtocol == .udp ? bandwidthBitsPerSecond : nil
        )
    }

    private func saveResult() {
        let result = TestResult(
            serverAddress: serverAddress.trimmingCharacters(in: .whitespaces),
            port: port,
            transport: selectedProtocol,
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

}
