import Foundation
import Observation
import IperfSwift

@Observable
final class IperfTestRunner {
    var isRunning = false
    var dataPoints: [DataPoint] = []
    var currentThroughputMbps: Double = 0
    var totalBytesTransferred: Int = 0
    var stateDescription: String = "Ready"
    var errorMessage: String?
    var elapsedTime: TimeInterval = 0
    var lastJitter: Double = 0
    var totalLostPackets: Int = 0
    var totalPacketsSent: Int = 0
    var lastRtt: Double = 0
    var isServerMode: Bool = false
    var serverPort: Int = 5201

    private var runner: IperfRunner?
    private var startTime: Date?
    private var stoppedByUser = false

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
        protocolType: String,
        direction: String,
        streams: Int,
        duration: TimeInterval
    ) {
        reset()
        isRunning = true
        isServerMode = false
        stateDescription = "Connecting..."

        var config = IperfConfiguration()
        config.address = address
        config.port = port
        config.role = .client
        config.prot = protocolType == "UDP" ? .udp : .tcp
        config.reverse = direction == "Download" ? .download : .upload
        config.numStreams = streams
        config.duration = duration

        let newRunner = IperfRunner(with: config)
        self.runner = newRunner
        startTime = Date()

        newRunner.start(
            { [weak self] result in
                self?.handleResult(result)
            },
            { [weak self] error in
                self?.handleError(error)
            },
            { [weak self] state in
                self?.handleState(state)
            }
        )
    }

    func startServer(port: Int) {
        reset()
        isRunning = true
        isServerMode = true
        serverPort = port
        stateDescription = "Listening on port \(port)..."

        var config = IperfConfiguration()
        config.port = port
        config.role = .server

        let newRunner = IperfRunner(with: config)
        self.runner = newRunner
        startTime = Date()

        newRunner.start(
            { [weak self] result in
                self?.handleResult(result)
            },
            { [weak self] error in
                self?.handleError(error)
            },
            { [weak self] state in
                self?.handleState(state)
            }
        )
    }

    func stop() {
        stoppedByUser = true
        runner?.stop()
        isRunning = false
        stateDescription = "Ready"
    }

    private func reset() {
        stoppedByUser = false
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
        errorMessage = String(describing: error)
        isRunning = false
        stateDescription = "Error"
    }

    private func handleState(_ state: IperfRunnerState) {
        guard !stoppedByUser else { return }
        switch state {
        case .running:
            stateDescription = "Running"
        case .finished:
            isRunning = false
            stateDescription = "Completed"
        case .initialising:
            stateDescription = "Initializing..."
        case .error:
            isRunning = false
            stateDescription = "Error"
        case .stopping:
            stateDescription = "Stopping..."
        default:
            break
        }
    }
}
