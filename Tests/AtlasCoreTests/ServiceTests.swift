#if !ATLAS_STANDALONE_CHECKS && canImport(XCTest)
import XCTest
#endif
import Foundation
#if !ATLAS_STANDALONE_CHECKS
@testable import WiFiAtlas
#endif
@testable import AtlasCore

final class FakeTransport: SpeedTransport {
    var calls = 0
    var cancelled = false
    var failAt: Int?
    var requests: [URLRequest] = []
    func transfer(_ request: URLRequest, upload: Data?) async throws -> Transfer {
        try Task.checkCancellation()
        calls += 1; requests.append(request)
        if cancelled { throw CancellationError() }
        if calls == failAt { throw URLError(.timedOut) }
        let bytes = upload?.count ?? Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "bytes" })?.value ?? "0") ?? 0
        return Transfer(bytes: bytes, seconds: 0.1)
    }
    func cancel() { cancelled = true }
}
final class BlockingTransport: SpeedTransport {
    private let lock = NSLock()
    private var pending: CheckedContinuation<Transfer, Error>?
    func transfer(_ request: URLRequest, upload: Data?) async throws -> Transfer {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); pending = continuation; lock.unlock()
        }
    }
    func cancel() {
        lock.lock(); let continuation = pending; pending = nil; lock.unlock()
        continuation?.resume(throwing: URLError(.cancelled))
    }
}
final class ServiceTests: XCTestCase {
    @MainActor func testDeadlineStopsStalledTransfer() async {
        let service = SpeedService(transport: BlockingTransport(), duration: 0.02)
        let start = Date()
        do { _ = try await service.run(network: "home", route: "Wi-Fi") { _, _, _ in }; XCTFail("Expected deadline") } catch { XCTAssertTrue(Date().timeIntervalSince(start) < 1) }
    }
    @MainActor func testCappedTestNeverRequestsMoreThanBudget() async throws {
        let transport = FakeTransport()
        let service = SpeedService(transport: transport, byteBudget: 1000, phaseDuration: 0)
        let result = try await service.run(network: "test", route: "Wi-Fi") { _, _, _ in }
        XCTAssertEqual(result.bytes, 1000)
        XCTAssertEqual(result.download!, 0.06, accuracy: 0.0001)
        XCTAssertEqual(result.upload!, 0.02, accuracy: 0.0001)
        XCTAssertTrue(result.note.contains("Limit"))
        XCTAssertTrue(transport.requests.allSatisfy { $0.url?.host == "speed.cloudflare.com" })
    }
    @MainActor func testSuccessfulBothDirections() async throws {
        let transport = FakeTransport()
        let service = SpeedService(transport: transport, phaseDuration: 0)
        let result = try await service.run(network: "home", route: "Wi-Fi") { _, _, _ in }
        XCTAssertEqual(result.latency, 100)
        XCTAssertEqual(result.jitter, 0)
        XCTAssertEqual(result.download, 640)
        XCTAssertEqual(result.upload, 160)
        XCTAssertEqual(result.bytes, 10_000_000)
        XCTAssertEqual(result.network, "home")
        XCTAssertEqual(transport.requests.last?.httpMethod, "POST")
    }
    @MainActor func testPartialFailureKeepsCompletedMeasurements() async throws {
        let transport = FakeTransport(); transport.failAt = 7
        let result = try await SpeedService(transport: transport, phaseDuration: 0).run(network: "home", route: "Wi-Fi") { _, _, _ in }
        XCTAssertNotNil(result.download)
        XCTAssertNil(result.upload)
        XCTAssertTrue(result.note.contains("Partial"))
    }
    @MainActor func testInitialFailureThrows() async {
        let transport = FakeTransport(); transport.failAt = 1
        do { _ = try await SpeedService(transport: transport).run(network: "home", route: "Wi-Fi") { _, _, _ in }; XCTFail("Expected timeout") } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }
    @MainActor func testCancellation() async {
        let transport = FakeTransport()
        let service = SpeedService(transport: transport)
        let task = Task { try await service.run(network: "home", route: "Wi-Fi") { _, _, _ in } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testRepositoryReopensFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtlasTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let first = try LocalRepository(directory: directory)
            var archive = Archive(); archive.spaces = [Space(name: "Persisted home")]
            try first.save(archive)
        }
        let reopened = try LocalRepository(directory: directory)
        XCTAssertEqual(try reopened.load().spaces.first?.name, "Persisted home")
    }
    @MainActor func testRepositoryRoundtripAndUpdate() throws {
        let repository = try LocalRepository(inMemory: true)
        var archive = Archive(); archive.spaces = [Space(name: "Home")]
        try repository.save(archive)
        XCTAssertEqual(try repository.load().spaces.first?.name, "Home")
        archive.spaces[0].name = "Office"; try repository.save(archive)
        XCTAssertEqual(try repository.load().spaces.count, 1)
        XCTAssertEqual(try repository.load().spaces.first?.name, "Office")
    }
}
