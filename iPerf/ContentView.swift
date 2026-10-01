import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case speedTest
    case serverMode
    case result(TestResult)
}

struct ContentView: View {
    var testRunner: IperfTestRunner
    var serverRunner: IperfTestRunner
    @State private var selectedItem: SidebarItem? = .speedTest
    @State private var showingExporter = false
    @State private var exportDocument: TestExportDocument?
    @State private var showingClearConfirmation = false
    @State private var searchText = ""
    @Query(sort: \TestResult.date, order: .reverse) private var testResults: [TestResult]
    @Environment(\.modelContext) private var modelContext

    private var filteredResults: [TestResult] {
        guard !searchText.isEmpty else { return testResults }
        let needle = searchText.lowercased()
        return testResults.filter {
            $0.serverAddress.lowercased().contains(needle)
                || $0.protocolName.lowercased().contains(needle)
                || $0.direction.lowercased().contains(needle)
        }
    }

    private var groupedResults: [(title: String, results: [TestResult])] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [(String, [TestResult])] = [
            ("Today", []), ("Yesterday", []), ("This Week", []), ("This Month", []), ("Older", [])
        ]
        for result in filteredResults {
            if calendar.isDateInToday(result.date) {
                buckets[0].1.append(result)
            } else if calendar.isDateInYesterday(result.date) {
                buckets[1].1.append(result)
            } else if calendar.isDate(result.date, equalTo: now, toGranularity: .weekOfYear) {
                buckets[2].1.append(result)
            } else if calendar.isDate(result.date, equalTo: now, toGranularity: .month) {
                buckets[3].1.append(result)
            } else {
                buckets[4].1.append(result)
            }
        }
        return buckets.filter { !$0.1.isEmpty }
    }

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
                HStack {
                    Label("Server Mode", systemImage: "server.rack")
                    Spacer()
                    if serverRunner.isRunning && serverRunner.isServerMode {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }
                .tag(SidebarItem.serverMode)
            }

            if testResults.isEmpty {
                Section("History") {
                    Text("No tests yet")
                        .foregroundStyle(.tertiary)
                        .font(.subheadline)
                }
            } else if groupedResults.isEmpty {
                Section("History") {
                    Text("No matches")
                        .foregroundStyle(.tertiary)
                        .font(.subheadline)
                }
            } else {
                ForEach(groupedResults, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.results) { result in
                            historyRow(result)
                                .tag(SidebarItem.result(result))
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        if case .result(let selected) = selectedItem, selected == result {
                                            selectedItem = .speedTest
                                        }
                                        modelContext.delete(result)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search history")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        .navigationTitle("iPerf")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !testResults.isEmpty {
                    Menu {
                        Button("Export All as CSV...") {
                            exportAll(as: .csv)
                        }
                        Button("Export All as JSON...") {
                            exportAll(as: .json)
                        }
                        Divider()
                        Button("Clear All History...", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportDocument?.format == .json ? .json : .commaSeparatedText,
            defaultFilename: "iperf-results-\(Date().formatted(.iso8601.year().month().day()))"
        ) { _ in }
        .confirmationDialog("Clear all test history?", isPresented: $showingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                selectedItem = .speedTest
                for result in testResults {
                    modelContext.delete(result)
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .speedTest:
            SpeedTestView(runner: testRunner)
        case .serverMode:
            ServerModeView(runner: serverRunner)
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
                .foregroundStyle(result.directionKind.color)
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

            Text(result.date, format: Calendar.current.isDate(result.date, equalTo: .now, toGranularity: .year)
                    ? .dateTime.month(.abbreviated).day()
                    : .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func exportAll(as format: ExportFormat) {
        let content: String
        switch format {
        case .csv:
            content = TestResult.csvHeader + "\n" + testResults.map { $0.toCSVRow() }.joined(separator: "\n")
        case .json:
            content = "[" + testResults.map { $0.toJSON() }.joined(separator: ",\n") + "]"
        }
        exportDocument = TestExportDocument(content: content, format: format)
        showingExporter = true
    }
}

#Preview {
    ContentView(testRunner: IperfTestRunner(), serverRunner: IperfTestRunner())
        .modelContainer(for: TestResult.self, inMemory: true)
}
