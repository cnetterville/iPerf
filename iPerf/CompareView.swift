import SwiftUI
import Charts

struct CompareView: View {
    let first: TestResult
    let second: TestResult

    private var firstLabel: String { "A · \(first.date.formatted(date: .abbreviated, time: .shortened))" }
    private var secondLabel: String { "B · \(second.date.formatted(date: .abbreviated, time: .shortened))" }

    private struct Row: Identifiable {
        let title: String
        let a: Double
        let b: Double
        let format: (Double) -> String
        let higherIsBetter: Bool
        var id: String { title }
    }

    private var rows: [Row] {
        var list = [
            Row(title: "Average", a: first.averageThroughputMbps, b: second.averageThroughputMbps, format: formatSpeed, higherIsBetter: true),
            Row(title: "Peak", a: first.maxThroughputMbps, b: second.maxThroughputMbps, format: formatSpeed, higherIsBetter: true)
        ]
        if first.transport == .udp && second.transport == .udp {
            list.append(Row(title: "Jitter", a: first.jitter, b: second.jitter, format: { String(format: "%.2f ms", $0) }, higherIsBetter: false))
            list.append(Row(title: "Packet Loss", a: first.packetLossPercent, b: second.packetLossPercent, format: { String(format: "%.1f%%", $0) }, higherIsBetter: false))
        } else if first.transport == .tcp && second.transport == .tcp {
            list.append(Row(title: "RTT", a: first.rttMs, b: second.rttMs, format: { String(format: "%.1f ms", $0) }, higherIsBetter: false))
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                chart
                metrics
            }
            .padding(24)
        }
        .navigationTitle("Compare Results")
    }

    private var header: some View {
        HStack(spacing: 16) {
            summary(label: "A", result: first, color: .blue)
            summary(label: "B", result: second, color: .orange)
        }
    }

    private func summary(label: String, result: TestResult, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(result.formattedThroughput)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(result.serverAddress) · \(result.direction) · \(result.protocolName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(result.formattedDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .heroStyle()
    }

    private var chart: some View {
        let all = first.dataPoints.map(\.throughputMbps) + second.dataPoints.map(\.throughputMbps)
        let useGbps = (all.max() ?? 0) >= 1000
        let divisor = useGbps ? 1000.0 : 1.0
        let aLabel = firstLabel
        let bLabel = secondLabel

        return Chart {
            ForEach(first.dataPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Throughput", point.throughputMbps / divisor),
                    series: .value("Result", aLabel)
                )
                .foregroundStyle(by: .value("Result", aLabel))
                .interpolationMethod(.monotone)
            }
            ForEach(second.dataPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Throughput", point.throughputMbps / divisor),
                    series: .value("Result", bLabel)
                )
                .foregroundStyle(by: .value("Result", bLabel))
                .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([aLabel: Color.blue, bLabel: Color.orange])
        .chartXAxisLabel("Time (s)")
        .chartYAxisLabel(useGbps ? "Gbps" : "Mbps")
        .chartYScale(domain: .automatic(includesZero: true))
        .frame(height: 220)
        .cardStyle()
    }

    private var metrics: some View {
        Grid(alignment: .trailing, horizontalSpacing: 28, verticalSpacing: 12) {
            GridRow {
                Text("")
                Text("A").foregroundStyle(.blue)
                Text("B").foregroundStyle(.orange)
                Text("B vs A").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))

            Divider()

            ForEach(rows) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    Text(row.format(row.a)).monospacedDigit()
                    Text(row.format(row.b)).monospacedDigit()
                    deltaText(row)
                }
                .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func deltaText(_ row: Row) -> some View {
        if row.a > 0 {
            let change = (row.b - row.a) / row.a * 100
            let improved = row.higherIsBetter ? change > 0 : change < 0
            Text(String(format: "%+.1f%%", change))
                .monospacedDigit()
                .foregroundStyle(abs(change) < 0.5 ? Color.secondary : (improved ? Color.green : Color.red))
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
