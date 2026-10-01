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
}

/// Measures the TCP handshake time to a host:port. ICMP isn't available inside the app sandbox,
/// and the handshake to the iperf3 port is what the test itself will experience.
///
/// Uses a raw socket rather than `NWConnection`, whose path setup and scheduling add
/// 1-2 ms on a LAN and would swamp the real round-trip time.
enum LatencyProbe {
    static func measure(host: String, port: Int, samples: Int = 5) async -> LatencyResult? {
        // Untimed warm-up primes ARP/route caches; also bails out early if the host is unreachable.
        guard await connectTime(host: host, port: port) != nil else { return nil }

        var times: [Double] = []
        for index in 0..<samples {
            if Task.isCancelled { break }
            if let ms = await connectTime(host: host, port: port) {
                times.append(ms)
            }
            if index < samples - 1 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        guard let minimum = times.min(), let maximum = times.max() else { return nil }

        let average = times.reduce(0, +) / Double(times.count)
        let deviations = zip(times, times.dropFirst()).map { abs($0 - $1) }
        let jitter = deviations.isEmpty ? 0 : deviations.reduce(0, +) / Double(deviations.count)
        return LatencyResult(
            minMs: minimum,
            avgMs: average,
            maxMs: maximum,
            jitterMs: jitter,
            received: times.count,
            sent: samples
        )
    }

    nonisolated private static func connectTime(host: String, port: Int) async -> Double? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: timedConnect(host: host, port: port))
            }
        }
    }

    /// Times only the `connect` call (name resolution happens beforehand). Returns nil on failure or after 3 s.
    nonisolated private static func timedConnect(host: String, port: Int) -> Double? {
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
            if failed && errno == EINPROGRESS {
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if poll(&descriptor, 1, 3000) > 0 {
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
                    failed = error != 0
                }
            }
            let end = DispatchTime.now().uptimeNanoseconds

            if !failed {
                return Double(end - start) / 1_000_000
            }
        }
        return nil
    }
}
