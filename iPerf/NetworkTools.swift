import Foundation
import Darwin

struct LocalAddress: Identifiable, Hashable {
    let interface: String
    let address: String
    let isIPv6: Bool

    var id: String { interface + address }
}

enum NetworkInfo {
    private static let ignoredInterfacePrefixes = ["awdl", "llw", "ap", "utun", "anpi"]

    /// Routable IPv4/IPv6 addresses of this Mac, IPv4 first.
    static func localAddresses() -> [LocalAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [LocalAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let sa = entry.ifa_addr else { continue }

            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            let name = String(cString: entry.ifa_name)
            guard !ignoredInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            guard !address.lowercased().hasPrefix("fe80") else { continue }

            found.append(LocalAddress(interface: name, address: address, isIPv6: family == AF_INET6))
        }

        return found.sorted {
            if $0.isIPv6 != $1.isIPv6 { return !$0.isIPv6 }
            return $0.interface < $1.interface
        }
    }

    /// Every host address on this Mac's IPv4 subnets, capped at one /24 per interface.
    static func scanTargets() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var seen = Set<UInt32>()
        var hosts: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr, let netmask = entry.ifa_netmask,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }

            let name = String(cString: entry.ifa_name)
            guard !ignoredInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if mask < 0xFFFF_FF00 { mask = 0xFFFF_FF00 }

            let network = ip & mask
            let broadcast = network | ~mask
            guard broadcast > network + 1 else { continue }

            for host in (network + 1)..<broadcast where seen.insert(host).inserted {
                hosts.append(Self.dotted(host))
            }
        }
        return hosts
    }

    static func dotted(_ value: UInt32) -> String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }
}

struct LatencyResult: Equatable {
    var minMs: Double
    var avgMs: Double
    var maxMs: Double
    var jitterMs: Double
    var received: Int
    var sent: Int

    var lossPercent: Double {
        sent > 0 ? Double(sent - received) / Double(sent) * 100 : 0
    }

    /// Summarises round-trip samples; jitter is the mean absolute difference of consecutive samples.
    init?(times: [Double], sent: Int) {
        guard let minimum = times.min(), let maximum = times.max() else { return nil }
        let deviations = zip(times, times.dropFirst()).map { abs($0 - $1) }
        self.minMs = minimum
        self.avgMs = times.reduce(0, +) / Double(times.count)
        self.maxMs = maximum
        self.jitterMs = deviations.isEmpty ? 0 : deviations.reduce(0, +) / Double(deviations.count)
        self.received = times.count
        self.sent = sent
    }
}

/// Measures the TCP handshake time to a host:port. ICMP isn't available inside the app sandbox,
/// and the handshake to the iperf3 port is what the test itself will experience.
///
/// Uses a raw socket rather than `NWConnection`, whose path setup and scheduling add
/// 1-2 ms on a LAN and would swamp the real round-trip time.
enum LatencyProbe {
    /// With `acceptRefused`, a connection reset counts as a reply: the host answered, so the time to
    /// the RST is a valid round trip. This lets us probe a client that has no open port.
    static func measure(host: String, port: Int, samples: Int = 5, acceptRefused: Bool = false) async -> LatencyResult? {
        // Untimed warm-up primes ARP/route caches; also bails out early if the host is unreachable.
        guard await connectTime(host: host, port: port, acceptRefused: acceptRefused) != nil else { return nil }

        var times: [Double] = []
        for index in 0..<samples {
            if Task.isCancelled { break }
            if let ms = await connectTime(host: host, port: port, acceptRefused: acceptRefused) {
                times.append(ms)
            }
            if index < samples - 1 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        return LatencyResult(times: times, sent: samples)
    }

    nonisolated static func connectTime(
        host: String,
        port: Int,
        timeoutMs: Int32 = 3000,
        acceptRefused: Bool = false
    ) async -> Double? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: timedConnect(host: host, port: port, timeoutMs: timeoutMs, acceptRefused: acceptRefused))
            }
        }
    }

    /// Times only the `connect` call (name resolution happens beforehand). Returns nil on failure or timeout.
    nonisolated private static func timedConnect(host: String, port: Int, timeoutMs: Int32, acceptRefused: Bool) -> Double? {
        guard !host.isEmpty else { return nil }

        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var resolved: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &resolved) == 0, let first = resolved else { return nil }
        defer { freeaddrinfo(resolved) }

        for candidate in sequence(first: first, next: { $0.pointee.ai_next }) {
            let fd = socket(candidate.pointee.ai_family, candidate.pointee.ai_socktype, candidate.pointee.ai_protocol)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

            let start = DispatchTime.now().uptimeNanoseconds
            var failed = connect(fd, candidate.pointee.ai_addr, candidate.pointee.ai_addrlen) != 0
            var code = failed ? errno : 0
            if failed && code == EINPROGRESS {
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if poll(&descriptor, 1, timeoutMs) > 0 {
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
                    failed = error != 0
                    code = error
                }
            }
            let end = DispatchTime.now().uptimeNanoseconds

            if !failed || (acceptRefused && code == ECONNREFUSED) {
                return Double(end - start) / 1_000_000
            }
        }
        return nil
    }
}

nonisolated struct DiscoveredServer: Identifiable, Hashable, Sendable {
    let address: String
    let latencyMs: Double

    var id: String { address }
}

/// Finds iperf3 servers by connecting to the given port on every host of the local subnets.
/// iperf3 doesn't advertise itself over Bonjour, so a bounded connect scan is the only option.
enum ServerScanner {
    private static let concurrency = 48
    private static let timeoutMs: Int32 = 400

    static func scan(port: Int) -> AsyncStream<DiscoveredServer> {
        AsyncStream { continuation in
            let task = Task {
                let hosts = NetworkInfo.scanTargets()
                await withTaskGroup(of: DiscoveredServer?.self) { group in
                    var index = 0
                    while index < min(concurrency, hosts.count) {
                        let host = hosts[index]
                        group.addTask { await probe(host: host, port: port) }
                        index += 1
                    }
                    for await result in group {
                        if let result { continuation.yield(result) }
                        if index < hosts.count, !Task.isCancelled {
                            let host = hosts[index]
                            group.addTask { await probe(host: host, port: port) }
                            index += 1
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func probe(host: String, port: Int) async -> DiscoveredServer? {
        guard let ms = await LatencyProbe.connectTime(host: host, port: port, timeoutMs: timeoutMs) else { return nil }
        return DiscoveredServer(address: host, latencyMs: ms)
    }
}
