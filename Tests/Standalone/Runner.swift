import Foundation
import AtlasCore

// Small assertion adapter for Command Line Tools installations without XCTest.
class XCTestCase {}
func XCTFail(_ message: String = "Failure", file: StaticString = #file, line: UInt = #line) { fatalError(message, file: file, line: line) }
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { if !value() { XCTFail("Expected true", file: file, line: line) } }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows { if try value() != nil { XCTFail("Expected nil", file: file, line: line) } }
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows { if try value() == nil { XCTFail("Expected non-nil", file: file, line: line) } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { let lhs = try a(), rhs = try b(); if lhs != rhs { XCTFail("Expected \(lhs) == \(rhs)", file: file, line: line) } } catch { XCTFail(error.localizedDescription, file: file, line: line) } }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { if abs(a-b) > accuracy { XCTFail("Expected \(a) ≈ \(b)", file: file, line: line) } }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { if a <= b { XCTFail("Expected \(a) > \(b)", file: file, line: line) } }

@main struct Runner {
    @MainActor static func main() async throws {
        let core = AtlasCoreTests()
        core.testUnitsAndMissingValues()
        core.testSurveyAggregation()
        core.testSparseAndDistantAreasRemainUnknown()
        core.testRoomBoundariesPreventCrossWallInterpolation()
        try core.testArchiveRoundtripPreservesFloorAndConnection()
        core.testCSVQuotesAndMissingSpeed()
        core.testHeatLayerOrderingAndClampedCoordinates()
        let service = ServiceTests()
        try await service.testCappedTestNeverRequestsMoreThanBudget()
        try await service.testSuccessfulBothDirections()
        try await service.testPartialFailureKeepsCompletedMeasurements()
        await service.testInitialFailureThrows()
        await service.testCancellation()
        await service.testDeadlineStopsStalledTransfer()
        try service.testRepositoryRoundtripAndUpdate()
        try service.testRepositoryReopensFromDisk()
        let redesign = RedesignTests()
        redesign.testStrengthPresentationIsConsistentAndClamped()
        redesign.testTrafficRateUsesElapsedTime()
        redesign.testCounterResetAndSleepBaseline()
        redesign.testPlannerSpotsStayInsideRoomsAndStartNearRouter()
        redesign.testLayoutSnapshotSurvivesEdits()
        try redesign.testSurveyProgressRoundtripRestoresNextUnfinishedSpot()
        redesign.testMeshNetworkIdentityIgnoresBSSID()
        try await redesign.testStreamingUpdateArrivesBeforeTransferCompletes()
        try redesign.testVersionOneMigrationBacksUpAndPreservesSurvey()
        try redesign.testUnknownArchiveIsNotOverwritten()
        try redesign.testLegacyJSONWithoutAddedFieldsDecodes()
        try redesign.testWidgetSnapshotKeepsSeparateTestTimestamp()
        redesign.testSuitabilityDoesNotGuessMissingMeasurements()
        let info = ConnectionInfoTests()
        info.testMissingAddressesStayUnavailable()
        info.testIPv4RouterAndAutomaticSetup()
        info.testIPv6PrefixesStayAlignedAndMissingPrefixIsNotInvented()
        info.testDNSListsDeduplicateWithoutReordering()
        info.testRadioNamesAndUnknownValues()
        info.testPublicIPParserAcceptsOnlyIPAddresses()
        info.testDHCPServerOptionRequiresFourBytes()
        info.testCopyDetailsIncludesLabelsAndUnavailableFields()
        print("PASS: 36 checks — aggregation, units, sparse coverage, room boundaries, archive, CSV, heat layers, speed caps, both directions, partial failure, timeout, cancellation, hard deadline, Core Data, disk reopen, strength presentation, traffic counters, layout snapshots, survey planning/resume, mesh identity, streaming updates, migration, widgets, suitability, connection info, DNS, DHCP, IPv6, public-IP parsing.")
    }
}
