import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case speedTest
    case serverMode
    case result(TestResult)
}

struct ContentView: View {
    @State private var testRunner = IperfTestRunner()
    @State private var selectedItem: SidebarItem? = .speedTest
    @Query(sort: \TestResult.date, order: .reverse) private var testResults: [TestResult]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
    }

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("Tools") {
                Label("Speed Test", systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarItem.speedTest)
                Label("Server Mode", systemImage: "server.rack")
                    .tag(SidebarItem.serverMode)
            }

            Section("History") {
                if testResults.isEmpty {
                    Text("No tests yet")
                        .foregroundStyle(.tertiary)
                        .font(.subheadline)
                } else {
                    ForEach(testResults) { result in
                        historyRow(result)
                            .tag(SidebarItem.result(result))
                    }
                    .onDelete(perform: deleteResults)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        .navigationTitle("iPerf")
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .speedTest:
            SpeedTestView(runner: testRunner)
        case .serverMode:
            ServerModeView(runner: testRunner)
        case .result(let result):
            TestDetailView(result: result)
        case nil:
            ContentUnavailableView(
                "No Selection",
                systemImage: "gauge.with.dots.needle.33percent",
                description: Text("Select a tool or a previous test result")
            )
        }
    }

    private func historyRow(_ result: TestResult) -> some View {
        HStack {
            Image(systemName: result.directionSymbol)
                .foregroundStyle(result.direction == "Download" ? .blue : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.serverAddress)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(result.formattedThroughput)
                    Text("·")
                    Text(result.protocolName)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(result.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func deleteResults(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(testResults[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TestResult.self, inMemory: true)
}
