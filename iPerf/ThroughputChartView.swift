import SwiftUI
import Charts

struct ThroughputChartView: View {
    let dataPoints: [DataPoint]
    var lineColor: Color = .blue

    private var chartPoints: [DataPoint] {
        guard let first = dataPoints.first else { return dataPoints }
        if first.timestamp > 0.5 {
            var points = [DataPoint(timestamp: 0, throughputMbps: 0)]
            points.append(contentsOf: dataPoints)
            return points
        }
        return dataPoints
    }

    private var xMax: Double {
        dataPoints.map(\.timestamp).max() ?? 10
    }

    var body: some View {
        let useGbps = (dataPoints.map(\.throughputMbps).max() ?? 0) >= 1000
        let divisor = useGbps ? 1000.0 : 1.0

        Chart(chartPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Throughput", point.throughputMbps / divisor)
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
                y: .value("Throughput", point.throughputMbps / divisor)
            )
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: 0...xMax)
        .chartXAxisLabel("Time (s)")
        .chartYAxisLabel(useGbps ? "Gbps" : "Mbps")
        .chartYScale(domain: .automatic(includesZero: true))
        .frame(height: 200)
    }
}
