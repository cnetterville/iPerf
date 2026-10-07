import Foundation
import Testing
import IperfSwift
@testable import iPerf

// MARK: - TestProfile

struct TestProfileTests {
    private func profile(
        address: String = "192.168.1.10",
        port: Int = 5201,
        transport: TransportProtocol = .tcp,
        limit: Double = 100,
        unit: String = "Mbps"
    ) -> TestProfile {
        TestProfile(
            address: address, port: port, transport: transport, direction: .download,
            streams: 1, duration: 10, bandwidthLimit: limit, bandwidthUnit: unit
        )
    }

    @Test func validProfileIsValid() {
        #expect(profile().isValid)
    }

    @Test(arguments: ["", "   ", "\t"])
    func blankAddressIsInvalid(address: String) {
        #expect(!profile(address: address).isValid)
    }

    @Test func addressIsTrimmed() {
        #expect(profile(address: "  host.local ").trimmedAddress == "host.local")
    }

    @Test(arguments: [0, -1, 65536, 100_000])
    func outOfRangePortIsInvalid(port: Int) {
        #expect(!profile(port: port).isValid)
    }

    @Test(arguments: [1, 5201, 65535])
    func inRangePortIsValid(port: Int) {
        #expect(profile(port: port).isValid)
    }

    @Test(arguments: [0.0, -5.0, Double.nan, Double.infinity])
    func udpRequiresPositiveFiniteRate(limit: Double) {
        #expect(!profile(transport: .udp, limit: limit).isValid)
    }

    @Test func tcpIgnoresBandwidthLimit() {
        #expect(profile(transport: .tcp, limit: 0).isValid)
    }

    @Test func rateConvertsUnits() {
        #expect(profile(limit: 100, unit: "Mbps").rateBitsPerSecond == 100_000_000)
        #expect(profile(limit: 2, unit: "Gbps").rateBitsPerSecond == 2_000_000_000)
        #expect(profile(limit: 0.5, unit: "Mbps").rateBitsPerSecond == 500_000)
    }

    @Test(arguments: [0.0, -10.0, Double.nan, Double.infinity, -Double.infinity])
    func rateClampsBadInputToZero(limit: Double) {
        #expect(profile(limit: limit).rateBitsPerSecond == 0)
    }

    @Test func rateClampsHugeValuesWithoutTrapping() {
        // Double(UInt64.max / 2) rounds up to 2^63, which is still representable.
        #expect(profile(limit: 1e30, unit: "Gbps").rateBitsPerSecond == UInt64(1) << 63)
    }

    @Test func listRoundTripsThroughCodable() {
        var saved = profile(address: "10.0.0.2", port: 6000)
        saved.name = "Office"
        let decoded = TestProfile.decodeList(TestProfile.encodeList([saved]))
        #expect(decoded == [saved])
    }

    @Test func corruptListDecodesToEmpty() {
        #expect(TestProfile.decodeList(Data("not json".utf8)).isEmpty)
    }
}

// MARK: - CSV

@MainActor
struct CSVTests {
    private func result(notes: String = "", tags: String = "") -> TestResult {
        let result = TestResult(
            serverAddress: "10.0.0.1", port: 5201, transport: .tcp,
            direction: .download, streamCount: 2, testDuration: 10
        )
        result.notes = notes
        result.tags = tags
        return result
    }

    /// Minimal RFC 4180 parser for a single record.
    private func parse(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = row.makeIterator()
        var pending = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        current.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    @Test func plainFieldsAreNotQuoted() {
        let row = result(notes: "office", tags: "wifi").toCSVRow()
        #expect(row.hasSuffix(",office,wifi"))
    }

    @Test func commasQuotesAndNewlinesRoundTrip() {
        let notes = "5 GHz, \"mesh\" node\nsecond floor"
        let tags = "a,b"
        let fields = parse(result(notes: notes, tags: tags).toCSVRow())
        #expect(fields.count == TestResult.csvHeader.split(separator: ",").count)
        #expect(fields[13] == notes)
        #expect(fields[14] == tags)
    }

    @Test func quoteIsDoubled() {
        let row = result(notes: "say \"hi\"").toCSVRow()
        #expect(row.contains("\"say \"\"hi\"\"\""))
    }

    @Test func carriageReturnTriggersQuoting() {
        let row = result(notes: "a\rb").toCSVRow()
        #expect(row.contains("\"a\rb\""))
    }

    @Test func headerAndRowHaveSameColumnCount() {
        let fields = parse(result().toCSVRow())
        #expect(fields.count == TestResult.csvHeader.split(separator: ",").count)
    }
}

// MARK: - Latency

struct LatencyStatsTests {
    @Test func emptySamplesProduceNoResult() {
        #expect(LatencyResult(times: [], sent: 5) == nil)
    }

    @Test func singleSampleHasZeroJitter() throws {
        let stats = try #require(LatencyResult(times: [4.0], sent: 1))
        #expect(stats.minMs == 4 && stats.avgMs == 4 && stats.maxMs == 4)
        #expect(stats.jitterMs == 0)
        #expect(stats.lossPercent == 0)
    }

    @Test func computesMinAvgMaxAndJitter() throws {
        let stats = try #require(LatencyResult(times: [10, 20, 10, 30], sent: 4))
        #expect(stats.minMs == 10)
        #expect(stats.maxMs == 30)
        #expect(stats.avgMs == 17.5)
        // |10-20|, |20-10|, |10-30| -> mean 40/3
        #expect(abs(stats.jitterMs - 40.0 / 3.0) < 1e-9)
    }

    @Test func lossComesFromMissingSamples() throws {
        let stats = try #require(LatencyResult(times: [1, 2, 3, 4], sent: 5))
        #expect(stats.received == 4)
        #expect(abs(stats.lossPercent - 20) < 1e-9)
    }

    @Test func zeroSentMeansNoLoss() throws {
        let stats = try #require(LatencyResult(times: [1], sent: 0))
        #expect(stats.lossPercent == 0)
    }
}

struct LatencyProbeTests {
    /// A loopback listener on an OS-assigned port; the kernel completes handshakes without `accept`.
    private final class Listener {
        let fd: Int32
        let port: Int

        init?() {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bound == 0, listen(descriptor, 16) == 0 else { close(descriptor); return nil }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
            }
            guard named == 0 else { close(descriptor); return nil }
            fd = descriptor
            port = Int(UInt16(bigEndian: address.sin_port))
        }

        deinit { close(fd) }
    }

    @Test func measuresConnectTimeToOpenPort() async throws {
        let listener = try #require(Listener())
        let ms = await LatencyProbe.connectTime(host: "127.0.0.1", port: listener.port)
        withExtendedLifetime(listener) {}
        let value = try #require(ms)
        #expect(value >= 0 && value < 1000)
    }

    @Test func collectsAllSamples() async throws {
        let listener = try #require(Listener())
        let stats = await LatencyProbe.measure(host: "127.0.0.1", port: listener.port, samples: 3)
        withExtendedLifetime(listener) {}
        let value = try #require(stats)
        #expect(value.received == 3)
        #expect(value.lossPercent == 0)
    }

    @Test func refusedPortCountsOnlyWhenAccepted() async throws {
        let closedPort = try #require(Listener()).port   // listener is gone after this statement
        #expect(await LatencyProbe.connectTime(host: "127.0.0.1", port: closedPort) == nil)
        #expect(await LatencyProbe.connectTime(host: "127.0.0.1", port: closedPort, acceptRefused: true) != nil)
    }

    @Test func emptyHostFails() async {
        #expect(await LatencyProbe.connectTime(host: "", port: 5201) == nil)
    }

    @Test func dottedQuadFormatting() {
        #expect(NetworkInfo.dotted(0xC0A8_0101) == "192.168.1.1")
        #expect(NetworkInfo.dotted(0) == "0.0.0.0")
    }
}

// MARK: - IperfTestRunner

@MainActor
struct IperfTestRunnerTests {
    private func intervalResult(bytesPerSecond: Double = 125_000_000, peer: String? = nil) -> IperfIntervalResult {
        var result = IperfIntervalResult()
        result.totalBytes = UInt64(bytesPerSecond)
        result.throughput = IperfThroughput(bytesPerSecond: bytesPerSecond)
        result.peerAddress = peer
        return result
    }

    private func clientRunner() -> IperfTestRunner {
        let runner = IperfTestRunner()
        runner.activeProfile = TestProfile.defaults
        runner.isRunning = true
        runner.state = .running
        return runner
    }

    // Server restart state machine

    @Test func serverStaysListeningAndClearsSessionWhenClientFinishes() async throws {
        let runner = IperfTestRunner()
        runner.startServer(port: 54_871)
        defer { runner.stop() }

        runner.handleResult(intervalResult(peer: "10.0.0.7"))
        #expect(runner.connectedClient == "10.0.0.7")
        #expect(!runner.dataPoints.isEmpty)

        runner.handleState(.finished)
        #expect(runner.state == .listening)
        #expect(runner.isRunning)
        #expect(runner.connectedClient == nil)
        #expect(runner.dataPoints.isEmpty)
        #expect(runner.totalBytesTransferred == 0)

        // The restarted server reports .running once the library is waiting for a client.
        try await Task.sleep(for: .milliseconds(800))
        #expect(runner.isRunning)
        #expect(runner.state == .listening || runner.state == .running)
    }

    @Test func serverErrorsRestartInsteadOfFailing() {
        let runner = IperfTestRunner()
        runner.startServer(port: 54_872)
        defer { runner.stop() }

        runner.handleError(.IESERVERTERM)
        #expect(runner.state == .listening)
        #expect(runner.errorMessage == nil)
        #expect(runner.isRunning)

        runner.handleState(.error)
        #expect(runner.state == .listening)
    }

    @Test func repeatedFinishEventsScheduleOnlyOneRestart() {
        let runner = IperfTestRunner()
        runner.startServer(port: 54_873)
        defer { runner.stop() }

        runner.handleState(.finished)
        runner.handleState(.finished)
        runner.handleState(.error)
        #expect(runner.state == .listening)
        #expect(runner.isRunning)
    }

    @Test func stopCancelsPendingRestart() async throws {
        let runner = IperfTestRunner()
        runner.startServer(port: 54_874)

        runner.handleState(.finished)
        runner.stop()
        #expect(runner.state == .idle)
        #expect(!runner.isRunning)

        try await Task.sleep(for: .milliseconds(800))
        #expect(runner.state == .idle)
        #expect(!runner.isRunning)
    }

    @Test func eventsAfterStopAreIgnored() {
        let runner = IperfTestRunner()
        runner.startServer(port: 54_875)
        runner.stop()

        runner.handleState(.running)
        runner.handleError(.IECONNECT)
        #expect(runner.state == .idle)
        #expect(runner.errorMessage == nil)
    }

    // Client lifecycle and saving

    @Test func clientCompletionDeliversResultExactlyOnce() throws {
        let runner = clientRunner()
        var delivered: [TestResult] = []
        runner.onTestCompleted = { delivered.append($0) }

        runner.handleResult(intervalResult())
        runner.handleResult(intervalResult(bytesPerSecond: 250_000_000))
        runner.handleState(.finished)
        runner.handleState(.finished)

        #expect(runner.state == .completed)
        #expect(!runner.isRunning)
        let result = try #require(delivered.first)
        #expect(delivered.count == 1)
        #expect(result.serverAddress == TestProfile.defaults.address)
        #expect(result.status == "completed")
        #expect(result.dataPoints.count == 2)
        #expect(result.averageThroughputMbps == runner.averageThroughputMbps)
        #expect(result.maxThroughputMbps == runner.maxThroughputMbps)
    }

    @Test func clientFinishWithoutDataSavesNothing() {
        let runner = clientRunner()
        var called = false
        runner.onTestCompleted = { _ in called = true }

        runner.handleState(.finished)
        #expect(runner.state == .completed)
        #expect(!called)
    }

    @Test func clientErrorFailsWithFriendlyMessage() {
        let runner = clientRunner()
        runner.handleError(.IECONNECT)
        #expect(runner.state == .failed)
        #expect(!runner.isRunning)
        #expect(runner.errorMessage?.contains("Couldn't reach the server") == true)
    }

    @Test func stoppedClientDoesNotSave() {
        let runner = clientRunner()
        var called = false
        runner.onTestCompleted = { _ in called = true }

        runner.handleResult(intervalResult())
        runner.stop()
        runner.handleState(.finished)
        #expect(!called)
    }

    @Test func progressTracksDuration() {
        let runner = clientRunner()
        runner.testDuration = 10
        #expect(runner.progress == nil)

        runner.handleResult(intervalResult())
        runner.elapsedTime = 4
        #expect(runner.progress == 0.4)
        #expect(runner.remainingTime == 6)

        runner.elapsedTime = 12
        #expect(runner.progress == 1)
        #expect(runner.remainingTime == 0)
    }
}
