import Foundation
import CoreWLAN
import CoreLocation
import Network
import CoreData
import AtlasCore

@MainActor protocol WiFiMonitoring { func read() -> Reading; func scan() async throws -> [NearbyNetwork] }
struct NearbyNetwork: Identifiable {
    let id = UUID()
    let name: String
    let channel: Int
    let band: String
    let signal: Int
    let security: String
}
@MainActor final class WiFiService: NSObject, WiFiMonitoring, CLLocationManagerDelegate {
    private let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    var authorization: CLAuthorizationStatus { location.authorizationStatus }
    override init() { super.init(); location.delegate = self }
    func requestPermission() { location.requestWhenInUseAuthorization() }
    func read() -> Reading {
        guard let i = client.interface(), i.powerOn() else { return Reading() }
        let connected = i.serviceActive() && i.wlanChannel() != nil
        let rssi = i.rssiValue(), noise = i.noiseMeasurement(), rate = i.transmitRate()
        return Reading(ssid: i.ssid(), bssid: i.bssid(), rssi: connected && rssi < 0 ? Double(rssi) : nil, noise: connected && noise < 0 ? Double(noise) : nil, linkRate: connected && rate > 0 ? rate : nil, channel: i.wlanChannel()?.channelNumber, band: i.wlanChannel().map { Self.band($0.channelBand) }, connected: connected)
    }
    nonisolated static func band(_ band: CWChannelBand) -> String { switch band { case .band2GHz: return "2.4 GHz"; case .band5GHz: return "5 GHz"; case .band6GHz: return "6 GHz"; default: return "Unknown" } }
    func scan() async throws -> [NearbyNetwork] {
        // CoreWLAN scanning blocks: keep it off the UI executor.
        try await Task.detached(priority: .utility) {
            guard let interface = CWWiFiClient.shared().interface() else { return [] }
            return try interface.scanForNetworks(withSSID: nil).map { n in
                NearbyNetwork(name: n.ssid ?? "Hidden / unavailable", channel: n.wlanChannel?.channelNumber ?? 0, band: n.wlanChannel.map { Self.band($0.channelBand) } ?? "Unknown", signal: n.rssiValue, security: n.supportsSecurity(.none) ? "Open" : "Secured")
            }.sorted { $0.signal > $1.signal }
        }.value
    }
}

@MainActor protocol SurveyRepository { func load() throws -> Archive; func save(_ archive: Archive) throws }
@MainActor final class LocalRepository: SurveyRepository {
    let container: NSPersistentContainer
    init(inMemory: Bool = false, directory suppliedDirectory: URL? = nil) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription(); entity.name = "StoredArchive"; entity.managedObjectClassName = "NSManagedObject"
        let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.allowsExternalBinaryDataStorage = true
        entity.properties = [payload]; model.entities = [entity]
        container = NSPersistentContainer(name: "WiFiAtlas", managedObjectModel: model)
        let description: NSPersistentStoreDescription
        if inMemory { description = NSPersistentStoreDescription(); description.type = NSInMemoryStoreType }
        else {
            let directory = try suppliedDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("WiFiAtlas", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Atlas.sqlite"))
        }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
    }
    func load() throws -> Archive {
        guard let record = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "StoredArchive")).first, let data = record.value(forKey: "payload") as? Data else { return Archive() }
        var archive = try JSONDecoder().decode(Archive.self, from: data)
        guard (1...2).contains(archive.version) else { throw CocoaError(.fileReadUnknown) }
        if archive.version == 1 {
            if let storeURL = container.persistentStoreDescriptions.first?.url, storeURL.path != "/dev/null" {
                let backup = storeURL.deletingLastPathComponent().appendingPathComponent("Atlas-v1-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: [.atomic]) }
            }
            for s in archive.spaces.indices { for f in archive.spaces[s].floors.indices {
                let snapshot = LayoutSnapshot(archive.spaces[s].floors[f])
                for i in archive.spaces[s].floors[f].sessions.indices { archive.spaces[s].floors[f].sessions[i].layoutSnapshot = snapshot }
            } }
            archive.version = 2
            try save(archive)
        }
        return archive
    }
    func save(_ archive: Archive) throws {
        let context = container.viewContext
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "StoredArchive")).first
        let record = existing ?? NSEntityDescription.insertNewObject(forEntityName: "StoredArchive", into: context)
        record.setValue(try JSONEncoder().encode(archive), forKey: "payload")
        try context.save()
    }
}

struct Transfer { let bytes: Int; let seconds: Double }
protocol SpeedTransport: AnyObject { var onProgress: ((Int, Double) -> Void)? { get set }; func transfer(_ request: URLRequest, upload: Data?) async throws -> Transfer; func cancel() }
extension SpeedTransport { var onProgress: ((Int, Double) -> Void)? { get { nil } set {} } }
// Count streamed bytes without holding download bodies in memory.
final class HTTPTransport: NSObject, SpeedTransport, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Transfer, Error>?
    private var progressHandler: ((Int, Double) -> Void)?
    var onProgress: ((Int, Double) -> Void)? { get { lock.lock(); defer { lock.unlock() }; return progressHandler } set { lock.lock(); progressHandler = newValue; lock.unlock() } }
    private var tick = 0.0
    private var startedClock = 0.0
    private var received = 0
    private var uploaded = 0
    private var started = Date()
    private var task: URLSessionTask?
    private let lock = NSLock()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 12
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    func transfer(_ request: URLRequest, upload: Data?) async throws -> Transfer {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { c in
                lock.lock(); defer { lock.unlock() }
                if Task.isCancelled { c.resume(throwing: CancellationError()); return }
                continuation = c; received = 0; uploaded = 0; started = Date(); startedClock = ProcessInfo.processInfo.systemUptime; tick = 0
                task = upload.map { session.uploadTask(with: request, from: $0) } ?? session.dataTask(with: request)
                task?.resume()
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() { lock.lock(); task?.cancel(); lock.unlock() }
    func close() { session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func emitProgress(bytes: Int) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedClock
        guard elapsed - tick >= 0.25 else { lock.unlock(); return }
        tick = elapsed; let callback = progressHandler; lock.unlock(); callback?(bytes, elapsed)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { lock.lock(); received += data.count; emitProgress(bytes: received) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) { lock.lock(); uploaded = Int(totalBytesSent); emitProgress(bytes: uploaded) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation; continuation = nil
        let result = Transfer(bytes: task is URLSessionUploadTask ? uploaded : received, seconds: Date().timeIntervalSince(started))
        lock.unlock()
        if let error { c?.resume(throwing: error) } else { c?.resume(returning: result) }
    }
}
@MainActor protocol SpeedTesting {
    func run(network: String, route: String, progress: @escaping (String, Double, Int) -> Void) async throws -> SpeedResult
    func cancel()
}
@MainActor final class SpeedService: SpeedTesting {
    var onUpdate: ((TestUpdate) -> Void)?
    private var transferID = UUID()
    private let transport: SpeedTransport
    private let byteBudget: Int
    private let duration: Double
    private let phaseDuration: Double
    init(transport: SpeedTransport = HTTPTransport(), byteBudget: Int = 250_000_000, duration: Double = 30, phaseDuration: Double = 9) { self.transport = transport; self.byteBudget = byteBudget; self.duration = duration; self.phaseDuration = phaseDuration }
    func cancel() { transport.cancel() }
    func run(network: String, route: String, progress: @escaping (String, Double, Int) -> Void) async throws -> SpeedResult {
        var result = SpeedResult(); result.network = network; result.route = route
        let start = Date(), budget = byteBudget
        let deadline = Task { [transport, duration] in
            do { try await Task.sleep(for: .seconds(duration)); transport.cancel() } catch { }
        }
        defer { deadline.cancel(); transport.onProgress = nil; transferID = UUID() }
        result.trace = []
        var latencies: [Double] = []
        do {
            for index in 0..<5 {
                try Task.checkCancellation()
                progress("Measuring latency", Double(index) / 5 * 0.1, result.bytes)
                let transfer = try await transport.transfer(request(path: "__down?bytes=0", timeout: 5), upload: nil)
                latencies.append(transfer.seconds * 1000); result.bytes += transfer.bytes
            }
            result.latency = Statistics.mean(latencies)
            result.jitter = Statistics.mean(zip(latencies.dropFirst(), latencies).map { abs($0 - $1) })
            for isUpload in [false, true] {
                let phaseStart = Date(); var bytes = 0; var seconds = 0.0
                let phaseLimit = isUpload ? budget : budget * 3 / 4
                repeat {
                    try Task.checkCancellation()
                    let remainingTime = duration - Date().timeIntervalSince(start)
                    guard remainingTime > 0.15, phaseLimit - result.bytes > 0 else { break }
                    let count = min(isUpload ? 2_000_000 : 8_000_000, phaseLimit - result.bytes)
                    progress(isUpload ? "Testing upload" : "Testing download", min(0.98, Date().timeIntervalSince(start) / duration), result.bytes)
                    var req = request(path: isUpload ? "__up" : "__down?bytes=\(count)", timeout: min(10, remainingTime))
                    if isUpload { req.httpMethod = "POST"; req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
                    let token = UUID(); transferID = token
                    let baseBytes = result.bytes
                    var rateWindow: [(Int, Double)] = [(0, 0)]
                    let phase = isUpload ? "Upload" : "Download"
                    transport.onProgress = { [weak self] count, elapsed in
                        Task { @MainActor in
                            guard let self, self.transferID == token, elapsed > (rateWindow.last?.1 ?? 0) else { return }
                            rateWindow.append((count, elapsed))
                            while rateWindow.count > 2 && elapsed - rateWindow[1].1 >= 1 { rateWindow.removeFirst() }
                            let first = rateWindow[0]
                            let rate = Statistics.mbps(bytes: max(0, count - first.0), seconds: elapsed - first.1)
                            self.onUpdate?(TestUpdate(phase: phase, rate: rate, bytes: baseBytes + count))
                        }
                    }
                    let transfer = try await transport.transfer(req, upload: isUpload ? Data(repeating: 0x61, count: count) : nil)
                    result.bytes += transfer.bytes; bytes += transfer.bytes; seconds += transfer.seconds
                    let finalRate = Statistics.mbps(bytes: transfer.bytes, seconds: transfer.seconds)
                    onUpdate?(TestUpdate(phase: phase, rate: finalRate, bytes: result.bytes))
                    result.trace?.append(RateSample(download: isUpload ? nil : finalRate, upload: isUpload ? finalRate : nil))
                    if isUpload { result.upload = Statistics.mbps(bytes: bytes, seconds: seconds) } else { result.download = Statistics.mbps(bytes: bytes, seconds: seconds) }
                } while Date().timeIntervalSince(phaseStart) < phaseDuration && Date().timeIntervalSince(start) < duration - 0.15 && result.bytes < phaseLimit
                if isUpload { result.upload = Statistics.mbps(bytes: bytes, seconds: seconds) } else { result.download = Statistics.mbps(bytes: bytes, seconds: seconds) }
            }
            if result.bytes >= budget || Date().timeIntervalSince(start) >= duration - 1 { result.note = "Limit reached; throughput may not have stabilized." }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            result.note = "Partial test: \(error.localizedDescription)"
            if result.latency == nil && result.download == nil { throw error }
        }
        return result
    }
    private func request(path: String, timeout: Double) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/\(path)\(path.contains("?") ? "&" : "?")atlas=\(UUID().uuidString)")!)
        request.timeoutInterval = timeout
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
}
