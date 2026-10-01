import SwiftUI
import SwiftData

enum TransportProtocol: String, CaseIterable, Identifiable, Codable {
    case tcp = "TCP"
    case udp = "UDP"

    var id: String { rawValue }
}

enum TestDirection: String, CaseIterable, Identifiable, Codable {
    case download = "Download"
    case upload = "Upload"

    var id: String { rawValue }

    var symbol: String {
        self == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    var color: Color {
        self == .download ? .blue : .green
    }
}

struct DataPoint: Codable, Identifiable, Sendable {
    var id = UUID()
    var timestamp: TimeInterval
    var throughputMbps: Double
    /// Per-stream rates in Mbps; only recorded when the test used more than one stream.
    var streamMbps: [Double]? = nil
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
    var notes: String = ""
    var tags: String = ""

    var tagList: [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var dataPoints: [DataPoint] {
        get {
            (try? JSONDecoder().decode([DataPoint].self, from: dataPointsData)) ?? []
        }
        set {
            dataPointsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var transport: TransportProtocol {
        TransportProtocol(rawValue: protocolName) ?? .tcp
    }

    var directionKind: TestDirection {
        TestDirection(rawValue: direction) ?? .download
    }

    init(
        serverAddress: String,
        port: Int,
        transport: TransportProtocol,
        direction: TestDirection,
        streamCount: Int,
        testDuration: Double,
        isServerMode: Bool = false
    ) {
        self.serverAddress = serverAddress
        self.port = port
        self.protocolName = transport.rawValue
        self.direction = direction.rawValue
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
        directionKind.symbol
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
            "Max: \(formatSpeed(maxThroughputMbps))",
            "Transferred: \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .binary))"
        ]
        if transport == .udp {
            lines.append("Jitter: \(String(format: "%.2f ms", jitter))")
            lines.append("Packet Loss: \(String(format: "%.1f%%", packetLossPercent))")
        } else {
            lines.append("RTT: \(String(format: "%.1f ms", rttMs))")
        }
        return lines.joined(separator: "\n")
    }

    func toCSVRow() -> String {
        let dateStr = ISO8601DateFormatter().string(from: date)
        let fields: [String] = [
            dateStr, serverAddress, "\(port)", protocolName, direction, "\(streamCount)",
            "\(testDuration)", "\(averageThroughputMbps)", "\(maxThroughputMbps)", "\(totalBytes)",
            "\(jitter)", "\(packetLossPercent)", "\(rttMs)", notes, tags
        ]
        return fields.map(Self.csvEscape).joined(separator: ",")
    }

    static var csvHeader: String {
        "Date,Server,Port,Protocol,Direction,Streams,Duration,AvgMbps,MaxMbps,Bytes,Jitter,PacketLoss%,RTTms,Notes,Tags"
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
            "notes": notes,
            "tags": tagList,
            "dataPoints": dataPoints.map { ["time": $0.timestamp, "mbps": $0.throughputMbps] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

}

func formatSpeed(_ mbps: Double) -> String {
    if mbps >= 1000 {
        return String(format: "%.2f Gbps", mbps / 1000)
    }
    return String(format: "%.1f Mbps", mbps)
}
