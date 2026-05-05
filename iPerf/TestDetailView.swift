import SwiftUI
import UniformTypeIdentifiers

struct TestDetailView: View {
    let result: TestResult
    @State private var showingExporter = false
    @State private var exportFormat: ExportFormat = .csv
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                summaryCard

                if !result.dataPoints.isEmpty {
                    ThroughputChartView(
                        dataPoints: result.dataPoints,
                        lineColor: result.direction == "Download" ? .blue : .green
                    )
                    .padding()
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }

                detailStats
            }
            .padding(24)
        }
        .navigationTitle("Test Result")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.summaryText, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    Menu {
                        Button("Export CSV...") {
                            exportFormat = .csv
                            showingExporter = true
                        }
                        Button("Export JSON...") {
                            exportFormat = .json
                            showingExporter = true
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: TestExportDocument(
                content: exportFormat == .csv
                    ? TestResult.csvHeader + "\n" + result.toCSVRow()
                    : result.toJSON(),
                format: exportFormat
            ),
            contentType: exportFormat == .csv ? .commaSeparatedText : .json,
            defaultFilename: "iperf-result-\(result.date.formatted(.iso8601.year().month().day()))"
        ) { _ in }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            Image(systemName: result.directionSymbol)
                .font(.system(size: 28))
                .foregroundStyle(result.direction == "Download" ? .blue : .green)

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
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var detailStats: some View {
        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
            GridRow {
                statLabel("Server")
                statValue("\(result.serverAddress):\(result.port)")
            }
            GridRow {
                statLabel("Average Speed")
                statValue(result.formattedThroughput)
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
            if result.protocolName == "UDP" {
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
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }

    private func statValue(_ text: String) -> some View {
        Text(text)
            .fontWeight(.medium)
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        }
        return String(format: "%.1f Mbps", mbps)
    }
}

enum ExportFormat {
    case csv, json
}

struct TestExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }

    let content: String
    let format: ExportFormat

    init(content: String, format: ExportFormat) {
        self.content = content
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        content = ""
        format = .csv
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
