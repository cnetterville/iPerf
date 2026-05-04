import SwiftUI
import Charts

struct ThroughputChartView: View {
    let dataPoints: [DataPoint]
    var lineColor: Color = .blue

    private var maxThroughput: Double {
        dataPoints.map(\.throughputMbps).max() ?? 0
    }

    private var useGbps: Bool {
        maxThroughput >= 1000
    }

    private func scaledValue(_ mbps: Double) -> Double {
        useGbps ? mbps / 1000 : mbps
    }

    var body: some View {
        Chart(dataPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Throughput", scaledValue(point.throughputMbps))
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [lineColor.opacity(0.3), lineColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Throughput", scaledValue(point.throughputMbps))
            )
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxisLabel("Time (s)")
        .chartYAxisLabel(useGbps ? "Gbps" : "Mbps")
        .chartYScale(domain: .automatic(includesZero: true))
        .frame(height: 200)
    }
}
