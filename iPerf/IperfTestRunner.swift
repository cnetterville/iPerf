import Foundation
import Observation
import IperfSwift

enum TestState: Equatable {
    case idle, connecting, initializing, listening, running, stopping, completed, failed
}

@Observable
final class IperfTestRunner {
    var isRunning = false
    var dataPoints: [DataPoint] = []
    var currentThroughputMbps: Double = 0
    var totalBytesTransferred: Int = 0
    var state: TestState = .idle
    var errorMessage: String?
    var elapsedTime: TimeInterval = 0
    var lastJitter: Double = 0
    var totalLostPackets: Int = 0
    var totalPacketsSent: Int = 0
    var lastRtt: Double = 0
    var isServerMode: Bool = false
    var serverPort: Int = 5201
    var activeProfile: TestProfile?
    var testDuration: TimeInterval = 0
    var connectedClient: String?

    /// Called once when a client test finishes with data, whether or not a window is open.
    @ObservationIgnored var onTestCompleted: ((TestResult) -> Void)?

    private var runner: IperfRunner?
    private var runnerID = UUID()
    private var testStart: Date?
    private var rttTotal: Double = 0
    private var rttSamples = 0
    private var stoppedByUser = false
    private var pendingRestart = false

    var stateDescription: String {
        switch state {
        case .idle: "Ready"
        case .connecting: "Connecting..."
        case .initializing: "Initializing..."
        case .listening: "Listening on port \(serverPort)..."
        case .running: "Running"
        case .stopping: "Stopping..."
        case .completed: "Completed"
        case .failed: "Error"
        }
    }

    /// 0...1 progress of a client test, or nil while no data has arrived yet.
    var progress: Double? {
        guard !isServerMode, testDuration > 0, !dataPoints.isEmpty else { return nil }
        return min(elapsedTime / testDuration, 1)
    }

    var remainingTime: TimeInterval {
        max(testDuration - elapsedTime, 0)
    }

    var averageThroughputMbps: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.map(\.throughputMbps).reduce(0, +) / Double(dataPoints.count)
    }

    var maxThroughputMbps: Double {
        dataPoints.map(\.throughputMbps).max() ?? 0
    }

    var averageRttMs: Double {
        rttSamples > 0 ? rttTotal / Double(rttSamples) : 0
    }

    var packetLossPercent: Double {
        guard totalPacketsSent > 0 else { return 0 }
        return Double(totalLostPackets) / Double(totalPacketsSent) * 100
    }

    var formattedCurrentSpeed: String {
        if currentThroughputMbps >= 1000 {
            return String(format: "%.2f", currentThroughputMbps / 1000)
        }
        return String(format: "%.1f", currentThroughputMbps)
    }

    var speedUnit: String {
        currentThroughputMbps >= 1000 ? "Gbps" : "Mbps"
    }

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytesTransferred), countStyle: .binary)
    }

    func start(profile: TestProfile) {
        reset()
        activeProfile = profile
        testDuration = profile.duration
        isRunning = true
        isServerMode = false
        state = .connecting

        var config = IperfConfiguration()
        config.address = profile.trimmedAddress
        config.port = profile.port
        config.role = .client
        config.prot = profile.transport == .udp ? .udp : .tcp
        config.reverse = profile.direction == .download ? .download : .upload
        config.numStreams = profile.streams
        config.duration = profile.duration
        config.reporterInterval = 0.5
        config.timeout = 10
        if profile.transport == .udp { config.rate = profile.rateBitsPerSecond }

        startRunner(with: config)
    }

    func startServer(port: Int) {
        reset()
        isRunning = true
        isServerMode = true
        serverPort = port
        state = .listening

        var config = IperfConfiguration()
        config.address = nil
        config.port = port
        config.role = .server

        startRunner(with: config)
    }

    func stop() {
        stoppedByUser = true
        pendingRestart = false
        runner?.stop()
        runner = nil
        isRunning = false
        connectedClient = nil
        state = .idle
    }

    /// Builds a persistable result from the finished client test, or nil if there is nothing to save.
    func makeResult() -> TestResult? {
        guard let profile = activeProfile, !isServerMode, !dataPoints.isEmpty else { return nil }
        let result = TestResult(
            serverAddress: profile.trimmedAddress,
            port: profile.port,
            transport: profile.transport,
            direction: profile.direction,
            streamCount: profile.streams,
            testDuration: profile.duration
        )
        result.averageThroughputMbps = averageThroughputMbps
        result.maxThroughputMbps = maxThroughputMbps
        result.totalBytes = totalBytesTransferred
        result.jitter = lastJitter
        result.packetLossPercent = packetLossPercent
        result.rttMs = averageRttMs
        result.dataPoints = dataPoints
        result.status = "completed"
        return result
    }

    private func reset() {
        runner?.stop()
        runner = nil
        runnerID = UUID()
        stoppedByUser = false
        pendingRestart = false
        activeProfile = nil
        testDuration = 0
        errorMessage = nil
        connectedClient = nil
        resetMetrics()
    }

    private func resetMetrics() {
        dataPoints = []
        currentThroughputMbps = 0
        totalBytesTransferred = 0
        elapsedTime = 0
        lastJitter = 0
        totalLostPackets = 0
        totalPacketsSent = 0
        lastRtt = 0
        rttTotal = 0
        rttSamples = 0
        testStart = nil
    }

    func handleResult(_ result: IperfIntervalResult) {
        let mbps = result.throughput.Mbps
        currentThroughputMbps = mbps
        totalBytesTransferred += Int(result.totalBytes)

        let now = Date()
        if testStart == nil {
            let interval = result.streams.first?.intervalDuration ?? 0
            testStart = now.addingTimeInterval(-interval)
        }
        if let testStart {
            elapsedTime = now.timeIntervalSince(testStart)
        }

        var streamRates: [Double]?
        if result.streams.count > 1 {
            streamRates = result.streams.map { stream in
                guard stream.intervalDuration > 0 else { return 0 }
                return Double(stream.bytesTransferred) * 8 / stream.intervalDuration / 1_000_000
            }
        }
        dataPoints.append(DataPoint(timestamp: elapsedTime, throughputMbps: mbps, streamMbps: streamRates))

        if result.prot == .udp {
            lastJitter = result.averageJitter
            totalLostPackets += Int(result.totalLostPackets)
            totalPacketsSent += Int(result.totalPackets)
        }

        lastRtt = result.averageRtt
        if result.averageRtt > 0 {
            rttTotal += result.averageRtt
            rttSamples += 1
        }

        if isServerMode, let peer = result.peerAddress {
            connectedClient = peer
        }
    }

    func handleError(_ error: IperfError) {
        guard !stoppedByUser else { return }
        if isServerMode {
            scheduleServerRestart()
            return
        }
        errorMessage = friendlyMessage(for: error)
        isRunning = false
        state = .failed
    }

    private func friendlyMessage(for error: IperfError) -> String {
        switch error {
        case .IECONNECT, .IESTREAMCONNECT:
            return "Couldn't reach the server. Check the address, port, and that iperf3 is running there."
        case .IEACCESSDENIED:
            return "The server is busy running another test. Try again in a moment."
        case .IESERVERTERM:
            return "The server stopped unexpectedly."
        case .IECLIENTTERM:
            return "The client stopped unexpectedly."
        case .IECTRLCLOSE, .IESTREAMCLOSE, .IECTRLREAD, .IECTRLWRITE:
            return "The connection to the server was lost."
        case .IELISTEN, .IEREUSEADDR:
            return "Couldn't bind to that port — it may already be in use."
        case .IEBADPORT:
            return "Invalid port number."
        case .IETOTALRATE:
            return "Requested bandwidth exceeds the server's allowed rate."
        case .IEDURATION:
            return "Test duration is too long."
        case .IENUMSTREAMS:
            return "Too many parallel streams requested."
        case .IENEWTEST, .IEINITTEST, .INIT_ERROR, .INIT_ERROR_DEFAULTS:
            return "Couldn't start the test. Try again."
        case .IEAUTHTEST:
            return "Authentication with the server failed."
        case .UNKNOWN:
            return "An unknown error occurred."
        default:
            return error.debugDescription
        }
    }

    func handleState(_ runnerState: IperfRunnerState) {
        guard !stoppedByUser else { return }
        switch runnerState {
        case .running:
            state = .running
        case .finished:
            if isServerMode {
                scheduleServerRestart()
            } else {
                guard state != .completed else { return }
                isRunning = false
                state = .completed
                if let result = makeResult() {
                    onTestCompleted?(result)
                }
            }
        case .initialising:
            state = .initializing
        case .error:
            if isServerMode {
                scheduleServerRestart()
            } else {
                isRunning = false
                state = .failed
            }
        case .stopping:
            state = .stopping
        default:
            break
        }
    }

    private func scheduleServerRestart() {
        guard !pendingRestart && !stoppedByUser else { return }
        pendingRestart = true
        runner?.stop()
        runner = nil
        runnerID = UUID()
        state = .listening
        connectedClient = nil
        resetMetrics()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isServerMode, !self.stoppedByUser else { return }
            self.pendingRestart = false

            var config = IperfConfiguration()
            config.address = nil
            config.port = self.serverPort
            config.role = .server

            self.startRunner(with: config)
        }
    }

    private func startRunner(with config: IperfConfiguration) {
        let newRunner = IperfRunner(with: config)
        self.runner = newRunner
        let id = runnerID

        newRunner.start(
            { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.runnerID == id else { return }
                    self.handleResult(result)
                }
            },
            { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.runnerID == id else { return }
                    self.handleError(error)
                }
            },
            { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, self.runnerID == id else { return }
                    self.handleState(state)
                }
            }
        )
    }
}
