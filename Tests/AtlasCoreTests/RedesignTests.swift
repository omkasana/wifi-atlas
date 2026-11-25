import Foundation
#if !ATLAS_STANDALONE_CHECKS && canImport(XCTest)
import XCTest
#endif
#if !ATLAS_STANDALONE_CHECKS
@testable import WiFiAtlas
#endif
@testable import AtlasCore

final class StreamingTransport: SpeedTransport {
    var onProgress: ((Int, Double) -> Void)?
    private let lock = NSLock()
    private var running = false
    var isTransferring: Bool { lock.lock(); defer { lock.unlock() }; return running }
    private func setRunning(_ value: Bool) { lock.lock(); running = value; lock.unlock() }
    func transfer(_ request: URLRequest, upload: Data?) async throws -> Transfer {
        let bytes = upload?.count ?? Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "bytes" })?.value ?? "0") ?? 0
        if bytes > 0 {
            setRunning(true)
            onProgress?(bytes/2,0.05)
            try await Task.sleep(for: .milliseconds(30))
            onProgress?(bytes,0.1)
            try await Task.sleep(for: .milliseconds(10))
            setRunning(false)
        }
        return Transfer(bytes: bytes,seconds: 0.1)
    }
    func cancel() { setRunning(false) }
}
final class RedesignTests: XCTestCase {
    func testStrengthPresentationIsConsistentAndClamped() {
        XCTAssertNil(Strength.score(nil)); XCTAssertEqual(Strength.label(nil),"Unavailable")
        XCTAssertEqual(Strength.score(-100),0); XCTAssertEqual(Strength.score(-30),100)
        XCTAssertEqual(Strength.label(-50),"Excellent"); XCTAssertEqual(Strength.label(-60),"Good")
        XCTAssertEqual(Strength.label(-70),"Fair"); XCTAssertEqual(Strength.label(-85),"Weak")
        XCTAssertEqual(HeatLayer.signal.quality(-60),Strength.score(-60)!/100)
    }
    func testTrafficRateUsesElapsedTime() {
        var tracker = CounterTracker()
        XCTAssertNil(tracker.sample(received: 1000,sent: 500,time: 10).download)
        let next = tracker.sample(received: 1_001_000,sent: 250_500,time: 12)
        XCTAssertEqual(next.download,4); XCTAssertEqual(next.upload,1)
    }
    func testCounterResetAndSleepBaseline() {
        var tracker = CounterTracker(); _ = tracker.sample(received: 100,sent: 100,time: 1)
        XCTAssertNil(tracker.sample(received: 50,sent: 50,time: 2).download)
        XCTAssertEqual(tracker.sample(received: 50,sent: 50,time: 3).download,0)
        tracker.reset(); XCTAssertNil(tracker.sample(received: 10000,sent: 10000,time: 100).upload)
        XCTAssertNil(tracker.sample(received: 20000,sent: 20000,time: 100).upload)
    }
    func testPlannerSpotsStayInsideRoomsAndStartNearRouter() {
        var floor = Floor(name: "Office"); floor.rooms = [Room(name: "Desk room",origin: MapPoint(x: 0.1,y: 0.2),width: 0.4,height: 0.5)]; floor.routers = [RouterMarker(name: "Main",position: MapPoint(x: 0.1,y: 0.2))]
        let spots = SurveyPlanner.spots(for: floor)
        XCTAssertEqual(spots.count,5); XCTAssertTrue(spots.allSatisfy { floor.rooms[0].contains($0.position) })
        let distances = spots.map { hypot($0.position.x-0.1,$0.position.y-0.2) }
        XCTAssertEqual(distances,distances.sorted())
        XCTAssertTrue(SurveyPlanner.spots(for: Floor(name: "Empty")).isEmpty)
    }
    func testLayoutSnapshotSurvivesEdits() {
        var floor = Floor(name: "Home"); floor.rooms = [Room(name: "Original",origin: MapPoint(x: 0,y: 0),width: 1,height: 1)]; floor.routers = [RouterMarker(name: "Original router",position: MapPoint(x: 0.2,y: 0.2))]
        let snapshot = LayoutSnapshot(floor)
        floor.rooms[0].name = "Changed"; floor.routers?[0].position = MapPoint(x: 0.8,y: 0.8)
        XCTAssertEqual(snapshot.rooms[0].name,"Original"); XCTAssertEqual(snapshot.routers[0].position.x,0.2)
    }
    func testSurveyProgressRoundtripRestoresNextUnfinishedSpot() throws {
        var session = SurveySession(name: "Walkthrough")
        session.plannedSpots = (1...3).map { PlannedSpot(name: "Spot \($0)",position: MapPoint(x: Double($0)/4,y: 0.5)) }
        session.plannedSpots?[0].completedPointID = UUID(); session.plannedSpots?[1].skipped = true
        let restored = try JSONDecoder().decode(SurveySession.self,from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.nextSpot?.id,session.plannedSpots?[2].id)
        session.plannedSpots?[2].skipped = true; XCTAssertNil(session.nextSpot)
    }
    func testMeshNetworkIdentityIgnoresBSSID() {
        let a = Reading(ssid: "Home",bssid: "aa"), b = Reading(ssid: "Home",bssid: "bb")
        XCTAssertEqual(a.networkIdentity,b.networkIdentity); XCTAssertTrue(a.context != b.context)
        XCTAssertTrue(a.networkIdentity != Reading(ssid: "Office").networkIdentity)
    }
    @MainActor func testStreamingUpdateArrivesBeforeTransferCompletes() async throws {
        let transport = StreamingTransport()
        let streaming = SpeedService(transport: transport,byteBudget: 1000,phaseDuration: 0)
        var beforeCompletion = false; var phases = Set<String>()
        streaming.onUpdate = { update in if transport.isTransferring && (update.rate ?? 0) > 0 { beforeCompletion = true }; phases.insert(update.phase) }
        let result = try await streaming.run(network: "Home",route: "Wi-Fi") { _,_,_ in }
        XCTAssertTrue(beforeCompletion); XCTAssertTrue(phases.contains("Download")); XCTAssertTrue(phases.contains("Upload")); XCTAssertEqual(result.bytes,1000)
    }
    @MainActor func testVersionOneMigrationBacksUpAndPreservesSurvey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasMigration-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LocalRepository(directory: directory)
        var archive = Archive(); archive.version = 1
        var space = Space(name: "Old home"); space.floors[0].rooms = [Room(name: "Room",origin: MapPoint(x: 0,y: 0),width: 1,height: 1)]
        space.floors[0].sessions[0].points = [SurveyPoint(name: "Desk",position: MapPoint(x: 0.5,y: 0.5),readings: [Reading(rssi: -60,connected: true)])]; archive.spaces = [space]
        try repository.save(archive)
        let migrated = try repository.load()
        XCTAssertEqual(migrated.version,2); XCTAssertEqual(migrated.spaces[0].floors[0].sessions[0].points[0].name,"Desk")
        XCTAssertEqual(migrated.spaces[0].floors[0].sessions[0].layoutSnapshot?.rooms.first?.name,"Room")
        let backup = try JSONDecoder().decode(Archive.self,from: Data(contentsOf: directory.appendingPathComponent("Atlas-v1-backup.json")))
        XCTAssertEqual(backup.version,1)
    }
    @MainActor func testUnknownArchiveIsNotOverwritten() throws {
        let repository = try LocalRepository(inMemory: true)
        var archive = Archive(); archive.version = 99; try repository.save(archive)
        do { _ = try repository.load(); XCTFail("Expected unsupported archive") } catch { XCTAssertTrue(error is CocoaError) }
    }
    func testLegacyJSONWithoutAddedFieldsDecodes() throws {
        var archive = Archive(); archive.version = 1; archive.spaces = [Space(name: "Legacy")]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String:Any]
        var spaces = json["spaces"] as! [[String:Any]], floors = spaces[0]["floors"] as! [[String:Any]], sessions = floors[0]["sessions"] as! [[String:Any]]
        for key in ["layoutSnapshot","plannedSpots","profile"] { sessions[0].removeValue(forKey: key) }
        for key in ["routers","doors"] { floors[0].removeValue(forKey: key) }
        floors[0]["sessions"] = sessions; spaces[0]["floors"] = floors; json["spaces"] = spaces
        let decoded = try JSONDecoder().decode(Archive.self,from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.spaces[0].name,"Legacy"); XCTAssertNil(decoded.spaces[0].floors[0].routers)
    }
    func testWidgetSnapshotKeepsSeparateTestTimestamp() throws {
        let date = Date(timeIntervalSince1970: 1000), testDate = Date(timeIntervalSince1970: 500)
        let snapshot = WidgetSnapshot(date: date,network: "Home",strength: 70,strengthLabel: "Good",download: 120,upload: 30,testDate: testDate,space: "Office",completed: 3,total: 10)
        let restored = try JSONDecoder().decode(WidgetSnapshot.self,from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.testDate,testDate); XCTAssertEqual(restored.date,date); XCTAssertEqual(restored.completed,3)
    }
    func testSuitabilityDoesNotGuessMissingMeasurements() {
        XCTAssertTrue(Suitability.guidance(nil).contains("complete speed test"))
        var t = SpeedResult(); t.download = 100; t.upload = 20; t.latency = 15; t.jitter = 3
        XCTAssertTrue(Suitability.guidance(t).contains("not measured")); XCTAssertTrue(Suitability.guidance(t).contains("looks suitable"))
    }
}
