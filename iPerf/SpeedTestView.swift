import SwiftUI
import SwiftData

struct SpeedTestView: View {
    var runner: IperfTestRunner

    @AppStorage(ClientPrefs.serverAddress) private var serverAddress = TestProfile.defaults.address
    @AppStorage(ClientPrefs.port) private var port = TestProfile.defaults.port
    @AppStorage(ClientPrefs.transport) private var selectedProtocol = TestProfile.defaults.transport
    @AppStorage(ClientPrefs.direction) private var selectedDirection = TestProfile.defaults.direction
    @AppStorage(ClientPrefs.streamCount) private var streamCount = TestProfile.defaults.streams
    @AppStorage(ClientPrefs.duration) private var duration = TestProfile.defaults.duration
    @AppStorage(ClientPrefs.bandwidthLimit) private var bandwidthLimit = TestProfile.defaults.bandwidthLimit
    @AppStorage(ClientPrefs.bandwidthUnit) private var bandwidthUnit = TestProfile.defaults.bandwidthUnit
    @AppStorage(ClientPrefs.presets) private var presetsData = Data()

    @State private var showingError = false
    @State private var showingSavePreset = false
    @State private var presetName = ""
    @State private var latencyState = LatencyState.idle
    @State private var latencyTask: Task<Void, Never>?
    @State private var showingDiscovery = false
    @Query(sort: \TestResult.date, order: .reverse) private var testResults: [TestResult]

    private var profile: TestProfile {
        TestProfile(
            address: serverAddress,
            port: port,
            transport: selectedProtocol,
            direction: selectedDirection,
            streams: streamCount,
            duration: duration,
            bandwidthLimit: bandwidthLimit,
            bandwidthUnit: bandwidthUnit
        )
    }

    private var presets: [TestProfile] {
        TestProfile.decodeList(presetsData)
    }

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

                actionButtons

                if runner.isRunning || !runner.dataPoints.isEmpty {
                    Divider()
                    resultsSection
                }
            }
            .padding(24)
        }
        .navigationTitle("Speed Test")
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(runner.errorMessage ?? "An unknown error occurred")
        }
        .alert("Save Preset", isPresented: $showingSavePreset) {
            TextField("Name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the current server, protocol, direction, streams and duration.")
        }
        .onChange(of: runner.state) { _, newValue in
            if newValue == .failed && runner.errorMessage != nil {
                showingError = true
            }
        }
        .onChange(of: serverAddress) { resetLatency() }
        .onChange(of: port) { resetLatency() }
        .onDisappear { latencyTask?.cancel() }
    }

    // MARK: - Configuration

    private var configurationCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                Spacer()
                presetsMenu
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Server Address")
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
                        Button {
                            showingDiscovery = true
                        } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Find iperf3 servers on the local network")
                        .popover(isPresented: $showingDiscovery, arrowEdge: .bottom) {
                            DiscoveryView(port: port) { address in
                                serverAddress = address
                                showingDiscovery = false
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Port")
                    TextField("port", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Protocol")
                    Picker("Protocol", selection: $selectedProtocol) {
                        ForEach(TransportProtocol.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Direction")
                    Picker("Direction", selection: $selectedDirection) {
                        Label("Download", systemImage: "arrow.down").tag(TestDirection.download)
                        Label("Upload", systemImage: "arrow.up").tag(TestDirection.upload)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Parallel Streams")
                    Stepper("\(streamCount)", value: $streamCount, in: 1...64)
                        .frame(width: 140)
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Duration")
                    Stepper("\(Int(duration))s", value: $duration, in: 5...300, step: 5)
                        .frame(width: 140)
                }
            }

            if selectedProtocol == .udp {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Bandwidth Limit")
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button("\(preset.name) — \(preset.address), \(preset.summary)") {
                    apply(preset)
                }
            }
            if !presets.isEmpty {
                Divider()
                Menu("Delete Preset") {
                    ForEach(presets) { preset in
                        Button(preset.name, role: .destructive) {
                            deletePreset(preset)
                        }
                    }
                }
            }
            Divider()
            Button("Save Current as Preset…") {
                presetName = ""
                showingSavePreset = true
            }
            .disabled(!profile.isValid)
        } label: {
            Label("Presets", systemImage: "bookmark")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Actions Row

    private var actionButtons: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button {
                        if runner.isRunning {
                            runner.stop()
                        } else {
                            runner.start(profile: profile)
                        }
                    } label: {
                        Label(
                            runner.isRunning ? "Stop Test" : "Start Test",
                            systemImage: runner.isRunning ? "stop.fill" : "play.fill"
                        )
                        .font(.headline)
                        .frame(width: 160)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(runner.isRunning ? .red : .accentColor)
                    .disabled(!runner.isRunning && !profile.isValid)

                    Button {
                        measureLatency()
                    } label: {
                        Label("Test Latency", systemImage: "waveform.path.ecg")
                            .font(.headline)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(runner.isRunning || !profile.isValid || latencyState == .measuring)
                }
                .controlSize(.large)
            }

            LatencyReadout(state: latencyState)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        let shown = runner.activeProfile ?? profile
        return VStack(spacing: 20) {
            if runner.isRunning {
                progressSection
            }

            speedDisplay(for: shown)

            ThroughputChartView(
                dataPoints: runner.dataPoints,
                lineColor: shown.direction.color
            )
            .cardStyle()

            statsGrid(for: shown)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            if let progress = runner.progress {
                ProgressView(value: progress)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            HStack {
                if runner.progress != nil {
                    Text("\(clock(runner.elapsedTime)) of \(clock(runner.testDuration))")
                    Spacer()
                    Text("\(clock(runner.remainingTime)) left · ETA \(Date().addingTimeInterval(runner.remainingTime).formatted(date: .omitted, time: .standard))")
                } else {
                    Text(runner.stateDescription)
                    Spacer()
                    Text("\(clock(runner.testDuration)) test")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded())).formatted(.time(pattern: .minuteSecond))
    }

    private func speedDisplay(for shown: TestProfile) -> some View {
        VStack(spacing: 8) {
            Image(systemName: shown.direction.symbol)
                .font(.system(size: 28))
                .foregroundStyle(shown.direction.color)

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
                Text("\(shown.transport.rawValue) · \(shown.streams) stream\(shown.streams == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
        .heroStyle()
    }

    private func statsGrid(for shown: TestProfile) -> some View {
        StatRow {
            StatTile(title: "Elapsed", value: String(format: "%.1fs", runner.elapsedTime), icon: "clock")
            Divider().frame(height: 44)
            StatTile(title: "Transferred", value: runner.formattedBytes, icon: "arrow.left.arrow.right")
            Divider().frame(height: 44)
            if shown.transport == .udp {
                StatTile(title: "Jitter", value: String(format: "%.2f ms", runner.lastJitter), icon: "waveform.path")
                Divider().frame(height: 44)
                StatTile(title: "Loss", value: String(format: "%.1f%%", runner.packetLossPercent), icon: "exclamationmark.triangle")
            } else {
                StatTile(title: "RTT", value: String(format: "%.1f ms", runner.lastRtt), icon: "arrow.left.arrow.right.circle")
                Divider().frame(height: 44)
                StatTile(title: "Avg Speed", value: formatSpeed(runner.averageThroughputMbps), icon: "gauge.with.dots.needle.50percent")
            }
        }
    }

    // MARK: - Latency

    private func measureLatency() {
        latencyTask?.cancel()
        latencyState = .measuring
        let target = profile
        latencyTask = Task {
            let outcome = await LatencyProbe.measure(host: target.trimmedAddress, port: target.port)
            guard !Task.isCancelled else { return }
            let failure = "Couldn't connect to \(target.trimmedAddress):\(target.port.formatted(.number.grouping(.never)))"
            latencyState = LatencyState(outcome, failure: failure)
        }
    }

    private func resetLatency() {
        latencyTask?.cancel()
        latencyState = .idle
    }

    // MARK: - Presets

    private func apply(_ preset: TestProfile) {
        serverAddress = preset.address
        port = preset.port
        selectedProtocol = preset.transport
        selectedDirection = preset.direction
        streamCount = preset.streams
        duration = preset.duration
        bandwidthLimit = preset.bandwidthLimit
        bandwidthUnit = preset.bandwidthUnit
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var preset = profile
        preset.name = name
        var list = presets.filter { $0.name != name }
        list.append(preset)
        presetsData = TestProfile.encodeList(list)
    }

    private func deletePreset(_ preset: TestProfile) {
        presetsData = TestProfile.encodeList(presets.filter { $0.id != preset.id })
    }
}
