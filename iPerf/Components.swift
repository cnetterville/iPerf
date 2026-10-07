import SwiftUI

extension View {
    /// Standard container for grouped content (forms, charts, stat rows).
    func cardStyle() -> some View {
        padding()
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    /// Prominent Liquid Glass treatment reserved for the hero readout.
    func heroStyle() -> some View {
        frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: 20))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

enum LatencyState: Equatable {
    case idle, measuring
    case failed(String)
    case result(LatencyResult)

    init(_ outcome: LatencyResult?, failure: String) {
        self = outcome.map(LatencyState.result) ?? .failed(failure)
    }
}

struct LatencyReadout: View {
    let state: LatencyState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .measuring:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring latency…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case .result(let latency):
            HStack(spacing: 12) {
                Text(String(format: "%.1f ms avg", latency.avgMs))
                    .fontWeight(.semibold)
                Text(String(format: "min %.1f · max %.1f · jitter %.1f ms", latency.minMs, latency.maxMs, latency.jitterMs))
                    .foregroundStyle(.secondary)
                if latency.lossPercent > 0 {
                    Text(String(format: "%.0f%% lost", latency.lossPercent))
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline.monospacedDigit())
        }
    }
}

struct StatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .cardStyle()
    }
}
