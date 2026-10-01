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

struct StatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .cardStyle()
    }
}
