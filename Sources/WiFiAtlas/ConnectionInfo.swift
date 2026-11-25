import Foundation
import CoreWLAN
import SystemConfiguration
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo
import Darwin

struct ConnectionInfoRow: Identifiable, Sendable {
    let label: String
    let value: String
    var id: String { label }
    init(_ label: String, _ value: String?) { self.label = label; self.value = value?.isEmpty == false ? value! : "Unavailable" }
}
struct ConnectionInfoSection: Identifiable, Sendable {
    let title: String
    let rows: [ConnectionInfoRow]
    var id: String { title }
}
struct ConnectionInfoSnapshot: Sendable {
    var date: Date?
    var sections: [ConnectionInfoSection] = []
    var copyText: String {
        sections.map { section in section.title + "\n" + section.rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}

/// Read-only local configuration. This never scans nearby networks or contacts an external server.
enum ConnectionInfoService {
    static func read(interface name: String) -> ConnectionInfoSnapshot {
        let store = SCDynamicStoreCreate(nil, "WiFiAtlas Connection Info" as CFString, nil, nil)
        func values(_ key: String) -> [String: Any] { (SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]) ?? [:] }
        var serviceID: String?, serviceName: String?
        if let preferences = SCPreferencesCreate(nil, "WiFiAtlas" as CFString, nil), let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] {
            // Prefer an enabled service with active addressing when multiple configurations share an adapter.
            let candidates = services.filter { service in guard let interface = SCNetworkServiceGetInterface(service) else { return false }; return (SCNetworkInterfaceGetBSDName(interface) as String?) == name }
            let service = candidates.first { service in
                guard SCNetworkServiceGetEnabled(service), let id = SCNetworkServiceGetServiceID(service) as String? else { return false }
                return !values("State:/Network/Service/\(id)/IPv4").isEmpty || !values("State:/Network/Service/\(id)/IPv6").isEmpty
            }
                ?? candidates.first { SCNetworkServiceGetEnabled($0) } ?? candidates.first
            if let service { serviceID = SCNetworkServiceGetServiceID(service) as String?; serviceName = SCNetworkServiceGetName(service) as String? }
        }
        let base = serviceID.map { "State:/Network/Service/\($0)" }
        var ipv4 = base.map { values($0 + "/IPv4") } ?? [:]
        var ipv6 = base.map { values($0 + "/IPv6") } ?? [:]
        let fallback4 = values("State:/Network/Interface/\(name)/IPv4"), fallback6 = values("State:/Network/Interface/\(name)/IPv6")
        ipv4.merge(fallback4) { current, _ in current }; ipv6.merge(fallback6) { current, _ in current }
        var dns = base.map { values($0 + "/DNS") } ?? [:]
        let setup4 = serviceID.map { values("Setup:/Network/Service/\($0)/IPv4") } ?? [:]
        let setupDNS = serviceID.map { values("Setup:/Network/Service/\($0)/DNS") } ?? [:]
        dns.merge(setupDNS) { current, _ in current }
        let global4 = values("State:/Network/Global/IPv4"), global6 = values("State:/Network/Global/IPv6")
        let systemDNS = values("State:/Network/Global/DNS")
        let interface = CWWiFiClient.shared().interface(withName: name)
        let connected = interface?.powerOn() == true && interface?.wlanChannel() != nil
        let channel = connected ? interface?.wlanChannel() : nil
        let power = interface?.powerOn()
        let rssi = connected ? interface?.rssiValue() : nil, noise = connected ? interface?.noiseMeasurement() : nil
        let rate = connected ? interface?.transmitRate() : nil
        let txPower = connected ? interface?.transmitPower() : nil
        let hostname = SCDynamicStoreCopyLocalHostName(store).map { ($0 as String) + ".local" }
        var snapshot = ConnectionInfoSnapshot(date: Date())
        snapshot.sections = [ConnectionInfoSection(title: "Wi-Fi connection", rows: [
            ConnectionInfoRow("Status", power == nil ? "Adapter unavailable" : power == false ? "Wi-Fi off" : connected ? "Connected" : "Not connected"),
            ConnectionInfoRow("Network name (SSID)", connected ? interface?.ssid() : nil),
            ConnectionInfoRow("Security", connected ? interface.map { security($0.security().rawValue) } : nil),
            ConnectionInfoRow("Wi-Fi generation", connected ? interface.map { standard($0.activePHYMode().rawValue) } : nil),
            ConnectionInfoRow("Access point address (BSSID)", connected ? interface?.bssid() : nil)
        ])]
        snapshot.sections.append(ConnectionInfoSection(title: "IP addresses & router", rows: addressRows(ipv4: ipv4, ipv6: ipv6, setup: setup4)))
        if setup4["ConfigMethod"] as? String == "DHCP", let id = serviceID,
           let dhcp = SCDynamicStoreCopyDHCPInfo(store, id as CFString) {
            let server = ipv4Address(from: DHCPInfoGetOptionData(dhcp, 54) as Data?)
            let start = DHCPInfoGetLeaseStartTime(dhcp) as Date?, expiry = DHCPInfoGetLeaseExpirationTime(dhcp) as Date?
            snapshot.sections.append(ConnectionInfoSection(title: "Automatic address lease (DHCP)", rows: [
                ConnectionInfoRow("DHCP server", server),
                ConnectionInfoRow("Lease started", start.map { $0.formatted() }),
                ConnectionInfoRow("Lease expires", expiry.map { $0.formatted() })
            ]))
        }
        snapshot.sections.append(ConnectionInfoSection(title: "DNS & routing", rows: [
            ConnectionInfoRow("Wi-Fi DNS servers", joined(strings(dns["ServerAddresses"]))),
            ConnectionInfoRow("Wi-Fi search domains", joined(strings(dns["SearchDomains"]))),
            ConnectionInfoRow("Wi-Fi domain", dns["DomainName"] as? String),
            ConnectionInfoRow("System DNS servers", joined(strings(systemDNS["ServerAddresses"]))),
            ConnectionInfoRow("Primary IPv4 interface", global4["PrimaryInterface"] as? String),
            ConnectionInfoRow("Primary IPv6 interface", global6["PrimaryInterface"] as? String),
            ConnectionInfoRow("Mac local hostname", hostname)
        ]))
        snapshot.sections.append(ConnectionInfoSection(title: "Wi-Fi adapter", rows: [
            ConnectionInfoRow("Interface", name), ConnectionInfoRow("Network service", serviceName),
            ConnectionInfoRow("Reported hardware address (MAC)", interface?.hardwareAddress()),
            ConnectionInfoRow("Operating mode", interface.map { mode($0.interfaceMode().rawValue) }),
            ConnectionInfoRow("Country / region code", connected ? interface?.countryCode() : nil),
            ConnectionInfoRow("MTU", mtu(interface: name).map { "\($0) bytes" })
        ]))
        snapshot.sections.append(ConnectionInfoSection(title: "Radio details", rows: [
            ConnectionInfoRow("Band", channel.map { band($0.channelBand.rawValue) }),
            ConnectionInfoRow("Channel", channel.map { String($0.channelNumber) }),
            ConnectionInfoRow("Channel width", channel.map { width($0.channelWidth.rawValue) }),
            ConnectionInfoRow("Wi-Fi link rate", rate.flatMap { $0 > 0 ? String(format: "%.0f Mbps (not internet speed)", $0) : nil }),
            ConnectionInfoRow("Raw signal", rssi.flatMap { $0 < 0 ? "\($0) dBm" : nil }),
            ConnectionInfoRow("Background noise", noise.flatMap { $0 < 0 ? "\($0) dBm" : nil }),
            ConnectionInfoRow("Signal above noise", rssi.flatMap { signal in noise.flatMap { signal < 0 && $0 < 0 ? "\(signal - $0) dB" : nil } }),
            ConnectionInfoRow("Reported transmit power", txPower.flatMap { $0 > 0 ? "\($0) mW" : nil })
        ]))
        return snapshot
    }
    static func strings(_ value: Any?) -> [String] { (value as? [String] ?? []).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    static func joined(_ values: [String]) -> String? { values.isEmpty ? nil : values.joined(separator: "\n") }
    static func addressRows(ipv4: [String: Any], ipv6: [String: Any], setup: [String: Any]) -> [ConnectionInfoRow] {
        let v4 = strings(ipv4["Addresses"]), masks = ipv4["SubnetMasks"] as? [String] ?? []
        let v6 = ipv6["Addresses"] as? [String] ?? [], prefixes = ipv6["PrefixLength"] as? [NSNumber] ?? []
        let addresses6 = v6.enumerated().compactMap { i, address -> String? in
            guard !address.isEmpty else { return nil }
            return i < prefixes.count && (0...128).contains(prefixes[i].intValue) ? "\(address) /\(prefixes[i].intValue)" : address
        }
        let config = setup["ConfigMethod"] as? String
        return [
            ConnectionInfoRow("Local IPv4 address", joined(v4)),
            ConnectionInfoRow("Subnet mask", joined(masks)),
            ConnectionInfoRow("Router / gateway (IPv4)", ipv4["Router"] as? String),
            ConnectionInfoRow("IPv4 address setup", config.map { $0 == "DHCP" ? "Automatic (DHCP)" : $0 == "Manual" ? "Manual" : $0 == "INFORM" ? "Manual address, DHCP options" : $0 == "LinkLocal" ? "Self-assigned (link-local)" : $0 }),
            ConnectionInfoRow("IPv6 addresses / prefix", joined(addresses6)),
            ConnectionInfoRow("Router / gateway (IPv6)", ipv6["Router"] as? String)
        ]
    }
    static func security(_ value: Int) -> String { [0:"Open (no Wi-Fi encryption)",1:"WEP (legacy)",2:"WPA Personal",3:"WPA / WPA2 Personal",4:"WPA2 Personal",5:"Personal",6:"Dynamic WEP (legacy)",7:"WPA Enterprise",8:"WPA / WPA2 Enterprise",9:"WPA2 Enterprise",10:"Enterprise",11:"WPA3 Personal",12:"WPA3 Enterprise",13:"WPA2 / WPA3 Personal",14:"Enhanced Open (OWE)",15:"Open / Enhanced Open"][value] ?? "Unavailable" }
    static func standard(_ value: Int) -> String { [1:"802.11a",2:"802.11b",3:"802.11g",4:"Wi-Fi 4 (802.11n)",5:"Wi-Fi 5 (802.11ac)",6:"Wi-Fi 6 / 6E (802.11ax)",7:"Wi-Fi 7 (802.11be)"][value] ?? "Unavailable" }
    static func mode(_ value: Int) -> String { [0:"Not associated",1:"Connected client",2:"Computer-to-computer",3:"Access point"][value] ?? "Unavailable" }
    static func band(_ value: Int) -> String { [1:"2.4 GHz",2:"5 GHz",3:"6 GHz"][value] ?? "Unavailable" }
    static func width(_ value: Int) -> String { [1:"20 MHz",2:"40 MHz",3:"80 MHz",4:"160 MHz"][value] ?? "Unavailable" }
    static func mtu(interface: String) -> Int? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }; defer { freeifaddrs(addresses) }
        var cursor = addresses
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            if String(cString: item.pointee.ifa_name) == interface, item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = item.pointee.ifa_data {
                let size = Int(data.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu); return size > 0 ? size : nil
            }
        }
        return nil
    }
    static func ipv4Address(from data: Data?) -> String? {
        guard let data, data.count == 4 else { return nil }
        return data.map(String.init).joined(separator: ".")
    }
    static func publicIP(from trace: String) -> String? {
        guard let line = trace.split(separator: "\n").first(where: { $0.hasPrefix("ip=") }) else { return nil }
        let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET,value,&v4) == 1 || inet_pton(AF_INET6,value,&v6) == 1 ? value : nil
    }
}
