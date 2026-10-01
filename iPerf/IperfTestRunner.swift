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

    private var runner: IperfRunner?
    private var runnerID = UUID()
    private var startTime: Date?
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

    var averageThroughputMbps: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.map(\.throughputMbps).reduce(0, +) / Double(dataPoints.count)
    }

    var maxThroughputMbps: Double {
        dataPoints.map(\.throughputMbps).max() ?? 0
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

    func startClient(
        address: String,
        port: Int,
        protocolType: TransportProtocol,
        direction: TestDirection,
        streams: Int,
        duration: TimeInterval,
        rate: UInt64? = nil
    ) {
        reset()
        isRunning = true
        isServerMode = false
        state = .connecting

        var config = IperfConfiguration()
        config.address = address
        config.port = port
        config.role = .client
        config.prot = protocolType == .udp ? .udp : .tcp
        config.reverse = direction == .download ? .download : .upload
        config.numStreams = streams
        config.duration = duration
        config.reporterInterval = 0.5
        config.timeout = 10
        if let rate { config.rate = rate }

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
        state = .idle
    }

    private func reset() {
        runner?.stop()
        runner = nil
        runnerID = UUID()
        stoppedByUser = false
        pendingRestart = false
        dataPoints = []
        currentThroughputMbps = 0
        totalBytesTransferred = 0
        errorMessage = nil
        elapsedTime = 0
        lastJitter = 0
        totalLostPackets = 0
        totalPacketsSent = 0
        lastRtt = 0
    }

    private func handleResult(_ result: IperfIntervalResult) {
        let mbps = result.throughput.Mbps
        currentThroughputMbps = mbps
        totalBytesTransferred += Int(result.totalBytes)

        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }

        let point = DataPoint(timestamp: elapsedTime, throughputMbps: mbps)
        dataPoints.append(point)

        if result.prot == .udp {
            lastJitter = result.averageJitter
            totalLostPackets += Int(result.totalLostPackets)
            totalPacketsSent += Int(result.totalPackets)
        }

        lastRtt = result.averageRtt
    }

    private func handleError(_ error: IperfError) {
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

    private func handleState(_ runnerState: IperfRunnerState) {
        guard !stoppedByUser else { return }
        switch runnerState {
        case .running:
            state = .running
        case .finished:
            if isServerMode {
                scheduleServerRestart()
            } else {
                isRunning = false
                state = .completed
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
        dataPoints = []
        currentThroughputMbps = 0
        totalBytesTransferred = 0
        elapsedTime = 0

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
        startTime = Date()

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
