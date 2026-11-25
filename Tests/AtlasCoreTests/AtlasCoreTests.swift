import Foundation
#if !ATLAS_STANDALONE_CHECKS && canImport(XCTest)
import XCTest
#endif
@testable import AtlasCore

final class AtlasCoreTests: XCTestCase {
    func testUnitsAndMissingValues() {
        XCTAssertEqual(Statistics.mbps(bytes: 1_000_000, seconds: 2), 4)
        XCTAssertNil(Statistics.mbps(bytes: 5, seconds: 0))
        XCTAssertNil(Statistics.mean([]))
        XCTAssertNil(Reading(rssi: -60).snr)
        XCTAssertEqual(Reading(rssi: -60, noise: -90).snr, 30)
    }
    func testSurveyAggregation() {
        let point = sample(0.2, 0.2, [-60, -64, -62])
        XCTAssertEqual(point.meanSignal!, -62)
        XCTAssertEqual(point.variability!, sqrt(8.0 / 3), accuracy: 0.0001)
        XCTAssertNil(point.value(.download))
    }
    func testSparseAndDistantAreasRemainUnknown() {
        let point = sample(0.1, 0.1, [-60])
        XCTAssertEqual(Statistics.estimate(at: point.position, points: [point], rooms: [], layer: .signal), -60)
        XCTAssertNil(Statistics.estimate(at: MapPoint(x: 0.15, y: 0.15), points: [point], rooms: [], layer: .signal))
        XCTAssertNil(Statistics.estimate(at: MapPoint(x: 0.9, y: 0.9), points: [point], rooms: [], layer: .signal))
    }
    func testRoomBoundariesPreventCrossWallInterpolation() {
        let points = [sample(0.1, 0.1, [-60]), sample(0.2, 0.1, [-60]), sample(0.1, 0.2, [-60])]
        let p = MapPoint(x: 0.15, y: 0.15)
        XCTAssertEqual(Statistics.estimate(at: p, points: points, rooms: [], layer: .signal)!, -60, accuracy: 0.001)
        let rooms = [Room(name: "Other room", origin: MapPoint(x: 0.12, y: 0.12), width: 0.1, height: 0.1)]
        XCTAssertNil(Statistics.estimate(at: p, points: points, rooms: rooms, layer: .signal))
        XCTAssertNil(Statistics.estimate(at: MapPoint(x: 0.8, y: 0.8), points: points, rooms: rooms, layer: .signal))
    }
    func testArchiveRoundtripPreservesFloorAndConnection() throws {
        var archive = Archive(); var space = Space(name: "Home")
        space.floors[0].imageData = Data([1, 2, 3]); space.floors[0].sessions[0].points = [sample(0.3, 0.4, [-61])]
        archive.spaces = [space]
        let result = try JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(result.spaces[0].floors[0].sessions[0].points[0].position.x, 0.3)
        XCTAssertEqual(result.spaces[0].floors[0].imageData, Data([1, 2, 3]))
        XCTAssertEqual(result.spaces[0].id, space.id)
    }
    func testCSVQuotesAndMissingSpeed() {
        var session = SurveySession(name: "Survey")
        var point = sample(0.1, 0.2, [-60]); point.name = "Desk, \"north\""
        session.points = [point]
        let csv = Statistics.csv(session)
        XCTAssertTrue(csv.contains("\"Desk, \"\"north\"\"\""))
        XCTAssertTrue(csv.contains("download_mbps"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }
    func testHeatLayerOrderingAndClampedCoordinates() {
        XCTAssertGreaterThan(HeatLayer.latency.quality(20), HeatLayer.latency.quality(100))
        XCTAssertGreaterThan(HeatLayer.signal.quality(-50), HeatLayer.signal.quality(-80))
        XCTAssertEqual(MapPoint(x: -1, y: 2), MapPoint(x: 0, y: 1))
    }
    private func sample(_ x: Double, _ y: Double, _ signals: [Double]) -> SurveyPoint {
        SurveyPoint(name: "Spot", position: MapPoint(x: x, y: y), readings: signals.map { Reading(ssid: "Home", rssi: $0, noise: -95, connected: true) })
    }
}
