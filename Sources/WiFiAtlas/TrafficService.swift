import Foundation
import Darwin
import CoreWLAN
import AtlasCore

protocol TrafficMonitoring { func sample(interface: String) -> RateSample; func reset() }
final class TrafficService: TrafficMonitoring {
    private var tracker = CounterTracker()
    private var selected = ""
    func reset() { tracker.reset(); selected = "" }
    var interfaces: [String] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return [] }
        defer { freeifaddrs(addresses) }
        var names = Set<String>(); var cursor = addresses
        while let item = cursor { let name = String(cString: item.pointee.ifa_name); if name.hasPrefix("en") { names.insert(name) }; cursor = item.pointee.ifa_next }
        return names.sorted()
    }
    var wifiInterface: String { CWWiFiClient.shared().interface()?.interfaceName ?? "en0" }
    func sample(interface: String) -> RateSample {
        if interface != selected { tracker.reset(); selected = interface }
        let index = if_nametoindex(interface)
        guard index != 0 else { tracker.reset(); return RateSample() }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return RateSample() }
        var data = Data(count: size)
        let ok = data.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0) == 0 }
        guard ok else { return RateSample() }
        return data.withUnsafeBytes { buffer in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { break }
                if header.ifm_type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(info.ifm_index) == index { return tracker.sample(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes, time: ProcessInfo.processInfo.systemUptime) }
                }
                offset += length
            }
            tracker.reset(); return RateSample()
        }
    }
}
