import SwiftUI
import Charts

struct ThroughputChartView: View {
    let dataPoints: [DataPoint]
    var lineColor: Color = .blue

    @State private var selectedTime: Double?
    @State private var showStreams = false

    private static let origin = DataPoint(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
        timestamp: 0,
        throughputMbps: 0
    )

    private struct StreamSample: Identifiable {
        let time: Double
        let stream: Int
        let mbps: Double
        var id: String { "\(stream)-\(time)" }
    }

    private var hasStreamData: Bool {
        dataPoints.contains { ($0.streamMbps?.count ?? 0) > 1 }
    }

    private var chartPoints: [DataPoint] {
        guard let first = dataPoints.first, first.timestamp > 0.5 else { return dataPoints }
        return [Self.origin] + dataPoints
    }

    private var streamSamples: [StreamSample] {
        dataPoints.flatMap { point in
            (point.streamMbps ?? []).enumerated().map {
                StreamSample(time: point.timestamp, stream: $0.offset + 1, mbps: $0.element)
            }
        }
    }

    private func nearestPoint(to time: Double) -> DataPoint? {
        dataPoints.min { abs($0.timestamp - time) < abs($1.timestamp - time) }
    }

    var body: some View {
        let peak = dataPoints.max { $0.throughputMbps < $1.throughputMbps }
        let peakMbps = peak?.throughputMbps ?? 0
        let average = dataPoints.isEmpty ? 0 : dataPoints.map(\.throughputMbps).reduce(0, +) / Double(dataPoints.count)
        let useGbps = peakMbps >= 1000
        let divisor = useGbps ? 1000.0 : 1.0
        let xMax = max(dataPoints.last?.timestamp ?? 0, 1)
        let yMax = max(peakMbps / divisor * 1.25, 1)
        let selected = selectedTime.flatMap(nearestPoint(to:))

        VStack(alignment: .trailing, spacing: 8) {
            if hasStreamData {
                Toggle("Show streams", isOn: $showStreams)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Chart {
                totalMarks(divisor: divisor)
                if showStreams {
                    streamMarks(divisor: divisor)
                }
                averageMark(average: average, divisor: divisor, useGbps: useGbps)
                if dataPoints.count > 1, let peak {
                    peakMark(peak, divisor: divisor, useGbps: useGbps)
                }
                if let selected {
                    selectionMark(selected, divisor: divisor, useGbps: useGbps)
                }
            }
            .chartXSelection(value: $selectedTime)
            .chartXScale(domain: 0...xMax)
            .chartYScale(domain: 0...yMax)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel(useGbps ? "Gbps" : "Mbps")
            .frame(height: 200)
        }
    }

    @ChartContentBuilder
    private func totalMarks(divisor: Double) -> some ChartContent {
        ForEach(chartPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Throughput", point.throughputMbps / divisor)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [lineColor.opacity(showStreams ? 0.12 : 0.3), lineColor.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Throughput", point.throughputMbps / divisor)
            )
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func streamMarks(divisor: Double) -> some ChartContent {
        ForEach(streamSamples) { sample in
            LineMark(
                x: .value("Time", sample.time),
                y: .value("Stream", sample.mbps / divisor),
                series: .value("Series", sample.stream)
            )
            .foregroundStyle(by: .value("Stream", "Stream \(sample.stream)"))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func averageMark(average: Double, divisor: Double, useGbps: Bool) -> some ChartContent {
        if average > 0 {
            RuleMark(y: .value("Average", average / divisor))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("avg \(formatSpeed(average))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ChartContentBuilder
    private func peakMark(_ peak: DataPoint, divisor: Double, useGbps: Bool) -> some ChartContent {
        PointMark(
            x: .value("Time", peak.timestamp),
            y: .value("Throughput", peak.throughputMbps / divisor)
        )
        .symbolSize(40)
        .foregroundStyle(lineColor)
        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
            Text("peak \(formatSpeed(peak.throughputMbps))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(lineColor)
        }
    }

    @ChartContentBuilder
    private func selectionMark(_ point: DataPoint, divisor: Double, useGbps: Bool) -> some ChartContent {
        RuleMark(x: .value("Time", point.timestamp))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .foregroundStyle(.secondary.opacity(0.6))
            .annotation(
                position: .top,
                spacing: 0,
                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
            ) {
                VStack(spacing: 2) {
                    Text(formatSpeed(point.throughputMbps))
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(String(format: "%.1f s", point.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: .rect(cornerRadius: 6))
            }
    }
}
