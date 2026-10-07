import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct TestDetailView: View {
    @Bindable var result: TestResult
    var canRunAgain = true
    var onRunAgain: (TestResult) -> Void = { _ in }

    @State private var showingExporter = false
    @State private var exportDocument: TestExportDocument?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                summaryCard

                let dataPoints = result.dataPoints
                if !dataPoints.isEmpty {
                    ThroughputChartView(
                        dataPoints: dataPoints,
                        lineColor: result.directionKind.color
                    )
                    .cardStyle()
                }

                detailStats

                notesCard

                TrendChartView(current: result)
            }
            .padding(24)
        }
        .navigationTitle("Test Result")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onRunAgain(result)
                } label: {
                    Label("Run Again", systemImage: "arrow.clockwise")
                }
                .disabled(!canRunAgain)
                .help("Run this test again with the same settings")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.summaryText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export CSV...") {
                        exportDocument = TestExportDocument(
                            content: TestResult.csvHeader + "\n" + result.toCSVRow(),
                            format: .csv
                        )
                        showingExporter = true
                    }
                    Button("Export JSON...") {
                        exportDocument = TestExportDocument(content: result.toJSON(), format: .json)
                        showingExporter = true
                    }
                    Divider()
                    Button("Export Image (PNG)...") {
                        exportShareCard(.png)
                    }
                    Button("Export Report (PDF)...") {
                        exportShareCard(.pdf)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportDocument?.format.contentType ?? .commaSeparatedText,
            defaultFilename: "iperf-result-\(result.date.formatted(.iso8601.year().month().day()))"
        ) { _ in }
    }

    private func exportShareCard(_ format: ExportFormat) {
        let data = format == .png ? ShareRenderer.pngData(for: result) : ShareRenderer.pdfData(for: result)
        guard let data else { return }
        exportDocument = TestExportDocument(data: data, format: format)
        showingExporter = true
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            Image(systemName: result.directionSymbol)
                .font(.system(size: 28))
                .foregroundStyle(result.directionKind.color)

            Text(result.formattedThroughput)
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text("\(result.direction) · \(result.protocolName) · \(result.streamCount) stream\(result.streamCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(result.formattedDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .heroStyle()
    }

    private var detailStats: some View {
        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
            GridRow {
                statLabel("Server")
                statValue("\(result.serverAddress):\(result.port)")
            }
            GridRow {
                statLabel("Max Speed")
                statValue(formatSpeed(result.maxThroughputMbps))
            }
            GridRow {
                statLabel("Duration")
                statValue(String(format: "%.0fs", result.testDuration))
            }
            GridRow {
                statLabel("Transferred")
                statValue(ByteCountFormatter.string(fromByteCount: Int64(result.totalBytes), countStyle: .binary))
            }
            if result.transport == .udp {
                GridRow {
                    statLabel("Jitter")
                    statValue(String(format: "%.2f ms", result.jitter))
                }
                GridRow {
                    statLabel("Packet Loss")
                    statValue(String(format: "%.1f%%", result.packetLossPercent))
                }
            } else {
                GridRow {
                    statLabel("RTT")
                    statValue(String(format: "%.1f ms", result.rttMs))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.headline)

            TextField("Add a note (location, cable, Wi-Fi band…)", text: $result.notes, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)

            TextField("Tags, comma separated", text: $result.tags)
                .textFieldStyle(.roundedBorder)

            if !result.tagList.isEmpty {
                HStack(spacing: 6) {
                    ForEach(result.tagList, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }

    private func statValue(_ text: String) -> some View {
        Text(text)
            .fontWeight(.medium)
    }
}

/// Average throughput over time for results sharing the same server, protocol and direction.
struct TrendChartView: View {
    let current: TestResult
    @Query private var history: [TestResult]

    init(current: TestResult) {
        self.current = current
        let address = current.serverAddress
        var descriptor = FetchDescriptor<TestResult>(
            predicate: #Predicate { $0.serverAddress == address && !$0.isServerMode },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        _history = Query(descriptor)
    }

    private var matching: [TestResult] {
        history
            .filter { $0.protocolName == current.protocolName && $0.direction == current.direction }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        let results = matching
        if results.count >= 2 {
            let useGbps = (results.map(\.averageThroughputMbps).max() ?? 0) >= 1000
            let divisor = useGbps ? 1000.0 : 1.0

            VStack(alignment: .leading, spacing: 8) {
                Text("Trend — \(current.serverAddress) · \(current.protocolName) \(current.direction)")
                    .font(.headline)

                Chart {
                    ForEach(results) { item in
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Average", item.averageThroughputMbps / divisor)
                        )
                        .foregroundStyle(current.directionKind.color.opacity(0.6))
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Average", item.averageThroughputMbps / divisor)
                        )
                        .foregroundStyle(item.id == current.id ? Color.orange : current.directionKind.color)
                        .symbolSize(item.id == current.id ? 90 : 36)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxisLabel(useGbps ? "Gbps" : "Mbps")
                .frame(height: 160)

                Text("\(results.count) tests · highlighted point is this result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

enum ExportFormat {
    case csv, json, png, pdf

    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        case .png: .png
        case .pdf: .pdf
        }
    }
}

struct TestExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, .png, .pdf] }

    let data: Data
    let format: ExportFormat

    init(content: String, format: ExportFormat) {
        self.data = Data(content.utf8)
        self.format = format
    }

    init(data: Data, format: ExportFormat) {
        self.data = data
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        data = Data()
        format = .csv
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
