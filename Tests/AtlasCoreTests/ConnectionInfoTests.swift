import Foundation
#if !ATLAS_STANDALONE_CHECKS && canImport(XCTest)
import XCTest
#endif
#if !ATLAS_STANDALONE_CHECKS
@testable import WiFiAtlas
#endif

final class ConnectionInfoTests: XCTestCase {
    func testMissingAddressesStayUnavailable() {
        let rows = ConnectionInfoService.addressRows(ipv4: [:],ipv6: [:],setup: [:])
        XCTAssertTrue(rows.allSatisfy { $0.value == "Unavailable" })
    }
    func testIPv4RouterAndAutomaticSetup() {
        let rows = ConnectionInfoService.addressRows(ipv4: ["Addresses":["192.168.1.4"],"SubnetMasks":["255.255.255.0"],"Router":"192.168.1.1"],ipv6: [:],setup: ["ConfigMethod":"DHCP"])
        XCTAssertEqual(rows.first { $0.label == "Local IPv4 address" }?.value,"192.168.1.4")
        XCTAssertEqual(rows.first { $0.label == "Subnet mask" }?.value,"255.255.255.0")
        XCTAssertEqual(rows.first { $0.label == "Router / gateway (IPv4)" }?.value,"192.168.1.1")
        XCTAssertEqual(rows.first { $0.label == "IPv4 address setup" }?.value,"Automatic (DHCP)")
    }
    func testIPv6PrefixesStayAlignedAndMissingPrefixIsNotInvented() {
        let rows = ConnectionInfoService.addressRows(ipv4: [:],ipv6: ["Addresses":["","2001:db8::1","fe80::1%en0"],"PrefixLength":[128,64]],setup: [:])
        XCTAssertEqual(rows.first { $0.label == "IPv6 addresses / prefix" }?.value,"2001:db8::1 /64\nfe80::1%en0")
        let invalid = ConnectionInfoService.addressRows(ipv4: [:],ipv6: ["Addresses":["::1"],"PrefixLength":[999]],setup: [:])
        XCTAssertEqual(invalid.first { $0.label == "IPv6 addresses / prefix" }?.value,"::1")
    }
    func testDNSListsDeduplicateWithoutReordering() {
        XCTAssertEqual(ConnectionInfoService.strings(["1.1.1.1","","8.8.8.8","1.1.1.1"]),["1.1.1.1","8.8.8.8"])
        XCTAssertNil(ConnectionInfoService.joined([]))
        XCTAssertTrue(ConnectionInfoService.strings(123).isEmpty)
    }
    func testRadioNamesAndUnknownValues() {
        XCTAssertEqual(ConnectionInfoService.security(11),"WPA3 Personal")
        XCTAssertEqual(ConnectionInfoService.security(0),"Open (no Wi-Fi encryption)")
        XCTAssertEqual(ConnectionInfoService.standard(7),"Wi-Fi 7 (802.11be)")
        XCTAssertEqual(ConnectionInfoService.width(4),"160 MHz")
        XCTAssertEqual(ConnectionInfoService.band(3),"6 GHz")
        XCTAssertEqual(ConnectionInfoService.standard(99),"Unavailable")
    }
    func testPublicIPParserAcceptsOnlyIPAddresses() {
        XCTAssertEqual(ConnectionInfoService.publicIP(from: "fl=123\nip=203.0.113.8\nloc=IN\n"),"203.0.113.8")
        XCTAssertEqual(ConnectionInfoService.publicIP(from: "ip=2001:db8::8\n"),"2001:db8::8")
        XCTAssertNil(ConnectionInfoService.publicIP(from: "ip=not-an-address\n"))
        XCTAssertNil(ConnectionInfoService.publicIP(from: "ip=999.1.1.1\n"))
        XCTAssertNil(ConnectionInfoService.publicIP(from: "error=offline\n"))
    }
    func testDHCPServerOptionRequiresFourBytes() {
        XCTAssertEqual(ConnectionInfoService.ipv4Address(from: Data([192,168,0,1])),"192.168.0.1")
        XCTAssertNil(ConnectionInfoService.ipv4Address(from: nil))
        XCTAssertNil(ConnectionInfoService.ipv4Address(from: Data([192,168,0])))
    }
    func testCopyDetailsIncludesLabelsAndUnavailableFields() {
        let snapshot = ConnectionInfoSnapshot(date: nil,sections: [ConnectionInfoSection(title: "IP",rows: [ConnectionInfoRow("Local IP","192.168.0.2"),ConnectionInfoRow("Router",nil)])])
        XCTAssertEqual(snapshot.copyText,"IP\nLocal IP: 192.168.0.2\nRouter: Unavailable")
    }
}
