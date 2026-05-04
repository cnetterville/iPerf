import Foundation
import SwiftData

struct DataPoint: Codable, Identifiable, Sendable {
    var id = UUID()
    var timestamp: TimeInterval
    var throughputMbps: Double
}

@Model
final class TestResult {
    var id: UUID = UUID()
    var date: Date = Date()
    var serverAddress: String = ""
    var port: Int = 5201
    var protocolName: String = "TCP"
    var direction: String = "Download"
    var streamCount: Int = 1
    var testDuration: Double = 10
    var averageThroughputMbps: Double = 0
    var maxThroughputMbps: Double = 0
    var jitter: Double = 0
    var packetLossPercent: Double = 0
    var rttMs: Double = 0
    var totalBytes: Int = 0
    var dataPointsData: Data = Data()
    var isServerMode: Bool = false
    var status: String = "running"
    var errorMessage: String?

    var dataPoints: [DataPoint] {
        get {
            (try? JSONDecoder().decode([DataPoint].self, from: dataPointsData)) ?? []
        }
        set {
            dataPointsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        serverAddress: String,
        port: Int,
        protocolName: String,
        direction: String,
        streamCount: Int,
        testDuration: Double,
        isServerMode: Bool = false
    ) {
        self.serverAddress = serverAddress
        self.port = port
        self.protocolName = protocolName
        self.direction = direction
        self.streamCount = streamCount
        self.testDuration = testDuration
        self.isServerMode = isServerMode
    }

    var formattedThroughput: String {
        if averageThroughputMbps >= 1000 {
            return String(format: "%.2f Gbps", averageThroughputMbps / 1000)
        }
        return String(format: "%.1f Mbps", averageThroughputMbps)
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var directionSymbol: String {
        direction == "Download" ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }
}
