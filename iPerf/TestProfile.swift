import Foundation

enum ClientPrefs {
    static let serverAddress = "client.serverAddress"
    static let port = "client.port"
    static let transport = "client.protocol"
    static let direction = "client.direction"
    static let streamCount = "client.streamCount"
    static let duration = "client.duration"
    static let bandwidthLimit = "client.bandwidthLimit"
    static let bandwidthUnit = "client.bandwidthUnit"
    static let presets = "client.presets"
    static let serverPort = "server.port"
    static let notifyOnCompletion = "notifyOnCompletion"
    static let hideDockIcon = "hideDockIcon"
}

/// A complete set of client test parameters. Used for presets, "Run Again" and keyboard-driven starts.
struct TestProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var address: String
    var port: Int
    var transport: TransportProtocol
    var direction: TestDirection
    var streams: Int
    var duration: Double
    var bandwidthLimit: Double
    var bandwidthUnit: String

    static let defaults = TestProfile(
        address: "192.168.1.1",
        port: 5201,
        transport: .tcp,
        direction: .download,
        streams: 3,
        duration: 10,
        bandwidthLimit: 1,
        bandwidthUnit: "Mbps"
    )

    /// The profile currently stored in the client form's `@AppStorage` keys.
    static var current: TestProfile {
        let store = UserDefaults.standard
        let base = TestProfile.defaults
        return TestProfile(
            address: store.string(forKey: ClientPrefs.serverAddress) ?? base.address,
            port: store.object(forKey: ClientPrefs.port) as? Int ?? base.port,
            transport: TransportProtocol(rawValue: store.string(forKey: ClientPrefs.transport) ?? "") ?? base.transport,
            direction: TestDirection(rawValue: store.string(forKey: ClientPrefs.direction) ?? "") ?? base.direction,
            streams: store.object(forKey: ClientPrefs.streamCount) as? Int ?? base.streams,
            duration: store.object(forKey: ClientPrefs.duration) as? Double ?? base.duration,
            bandwidthLimit: store.object(forKey: ClientPrefs.bandwidthLimit) as? Double ?? base.bandwidthLimit,
            bandwidthUnit: store.string(forKey: ClientPrefs.bandwidthUnit) ?? base.bandwidthUnit
        )
    }

    func store() {
        let store = UserDefaults.standard
        store.set(address, forKey: ClientPrefs.serverAddress)
        store.set(port, forKey: ClientPrefs.port)
        store.set(transport.rawValue, forKey: ClientPrefs.transport)
        store.set(direction.rawValue, forKey: ClientPrefs.direction)
        store.set(streams, forKey: ClientPrefs.streamCount)
        store.set(duration, forKey: ClientPrefs.duration)
        store.set(bandwidthLimit, forKey: ClientPrefs.bandwidthLimit)
        store.set(bandwidthUnit, forKey: ClientPrefs.bandwidthUnit)
    }

    var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespaces)
    }

    var isValid: Bool {
        !trimmedAddress.isEmpty
            && (1...65535).contains(port)
            && (transport == .tcp || (bandwidthLimit.isFinite && bandwidthLimit > 0))
    }

    var rateBitsPerSecond: UInt64 {
        let mbps = bandwidthUnit == "Gbps" ? bandwidthLimit * 1000 : bandwidthLimit
        let bps = mbps * 1_000_000
        guard bps.isFinite, bps > 0 else { return 0 }
        return UInt64(min(bps, Double(UInt64.max / 2)))
    }

    var summary: String {
        "\(transport.rawValue) · \(direction.rawValue) · \(streams) stream\(streams == 1 ? "" : "s") · \(Int(duration))s"
    }

    static func decodeList(_ data: Data) -> [TestProfile] {
        (try? JSONDecoder().decode([TestProfile].self, from: data)) ?? []
    }

    static func encodeList(_ profiles: [TestProfile]) -> Data {
        (try? JSONEncoder().encode(profiles)) ?? Data()
    }
}
