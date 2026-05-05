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

    var summaryText: String {
        var lines = [
            "iPerf Test Result",
            "Date: \(formattedDate)",
            "Server: \(serverAddress):\(port)",
            "Protocol: \(protocolName)",
            "Direction: \(direction)",
            "Streams: \(streamCount)",
            "Duration: \(String(format: "%.0fs", testDuration))",
            "Average: \(formattedThroughput)",
            "Max: \(formatSpeedValue(maxThroughputMbps))",
            "Transferred: \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .binary))"
        ]
        if protocolName == "UDP" {
            lines.append("Jitter: \(String(format: "%.2f ms", jitter))")
            lines.append("Packet Loss: \(String(format: "%.1f%%", packetLossPercent))")
        } else {
            lines.append("RTT: \(String(format: "%.1f ms", rttMs))")
        }
        return lines.joined(separator: "\n")
    }

    func toCSVRow() -> String {
        let dateStr = ISO8601DateFormatter().string(from: date)
        return "\(dateStr),\(serverAddress),\(port),\(protocolName),\(direction),\(streamCount),\(testDuration),\(averageThroughputMbps),\(maxThroughputMbps),\(totalBytes),\(jitter),\(packetLossPercent),\(rttMs)"
    }

    static var csvHeader: String {
        "Date,Server,Port,Protocol,Direction,Streams,Duration,AvgMbps,MaxMbps,Bytes,Jitter,PacketLoss%,RTTms"
    }

    func toJSON() -> String {
        let dict: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: date),
            "server": serverAddress,
            "port": port,
            "protocol": protocolName,
            "direction": direction,
            "streams": streamCount,
            "duration": testDuration,
            "averageMbps": averageThroughputMbps,
            "maxMbps": maxThroughputMbps,
            "totalBytes": totalBytes,
            "jitter": jitter,
            "packetLossPercent": packetLossPercent,
            "rttMs": rttMs,
            "dataPoints": dataPoints.map { ["time": $0.timestamp, "mbps": $0.throughputMbps] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func formatSpeedValue(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        }
        return String(format: "%.1f Mbps", mbps)
    }
}
