import SwiftUI

/// Popover that scans the local subnets for hosts listening on the iperf3 port.
struct DiscoveryView: View {
    let port: Int
    var onSelect: (String) -> Void

    @State private var servers: [DiscoveredServer] = []
    @State private var scanning = false
    @State private var scanToken = 0
    @State private var ownAddresses = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("iperf3 Servers")
                    .font(.headline)
                Spacer()
                if scanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        scanToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Scan again")
                }
            }

            Text("Hosts on your local network accepting connections on port \(port.formatted(.number.grouping(.never))).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if servers.isEmpty {
                Text(scanning ? "Scanning…" : "No servers found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 2) {
                    ForEach(servers) { server in
                        Button {
                            onSelect(server.address)
                        } label: {
                            HStack {
                                Text(server.address)
                                    .font(.body.monospaced())
                                if ownAddresses.contains(server.address) {
                                    Text("this Mac")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.1f ms", server.latencyMs))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(width: 320)
        .task(id: scanToken) { await scan() }
    }

    private func scan() async {
        servers = []
        scanning = true
        ownAddresses = Set(NetworkInfo.localAddresses().map(\.address))
        for await server in ServerScanner.scan(port: port) {
            servers.append(server)
            servers.sort { $0.address.localizedStandardCompare($1.address) == .orderedAscending }
        }
        if !Task.isCancelled { scanning = false }
    }
}
