import SwiftUI

/// Self-contained, light-themed summary of a result, rendered to an image or PDF for sharing.
struct ShareCardView: View {
    let result: TestResult

    static let width: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Label("iPerf3 Result", systemImage: "speedometer")
                    .font(.headline)
                Spacer()
                Text(result.formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Image(systemName: result.directionSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(result.directionKind.color)
                Text(result.formattedThroughput)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                Text("\(result.direction) · \(result.protocolName) · \(result.streamCount) stream\(result.streamCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            let dataPoints = result.dataPoints
            if !dataPoints.isEmpty {
                ThroughputChartView(
                    dataPoints: dataPoints,
                    lineColor: result.directionKind.color,
                    showsControls: false
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                ForEach(statRows, id: \.0) { row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary)
                        Text(row.1).fontWeight(.medium)
                    }
                }
            }
            .font(.subheadline)

            if !result.notes.isEmpty || !result.tagList.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !result.notes.isEmpty {
                        Text(result.notes).font(.subheadline)
                    }
                    if !result.tagList.isEmpty {
                        Text(result.tagList.map { "#\($0)" }.joined(separator: "  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var statRows: [(String, String)] {
        var rows = [
            ("Server", "\(result.serverAddress):\(result.port)"),
            ("Average", formatSpeed(result.averageThroughputMbps)),
            ("Max", formatSpeed(result.maxThroughputMbps)),
            ("Duration", String(format: "%.0fs", result.testDuration)),
            ("Transferred", ByteCountFormatter.string(fromByteCount: Int64(result.totalBytes), countStyle: .binary))
        ]
        if result.transport == .udp {
            rows.append(("Jitter", String(format: "%.2f ms", result.jitter)))
            rows.append(("Packet Loss", String(format: "%.1f%%", result.packetLossPercent)))
        } else {
            rows.append(("RTT", String(format: "%.1f ms", result.rttMs)))
        }
        return rows
    }
}

#Preview {
    let result = TestResult(
        serverAddress: "192.168.1.20", port: 5201, transport: .tcp,
        direction: .download, streamCount: 4, testDuration: 10
    )
    result.averageThroughputMbps = 912
    result.maxThroughputMbps = 948
    result.totalBytes = 1_140_000_000
    result.rttMs = 0.8
    result.notes = "Office Wi-Fi, 5 GHz"
    result.tags = "wifi, office"
    result.dataPoints = (1...10).map {
        DataPoint(timestamp: Double($0), throughputMbps: 880 + Double($0 * 7 % 60), streamMbps: nil)
    }
    return ShareCardView(result: result)
}

enum ShareRenderer {
    @MainActor
    static func pngData(for result: TestResult) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(result: result))
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor
    static func pdfData(for result: TestResult) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(result: result))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var rendered = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            rendered = true
        }
        return rendered ? data as Data : nil
    }
}
