import Foundation

public struct Reading: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var ssid: String?
    public var bssid: String?
    public var rssi: Double?
    public var noise: Double?
    public var linkRate: Double?
    public var channel: Int?
    public var band: String?
    public var connected: Bool
    public var snr: Double? { guard let rssi, let noise else { return nil }; return rssi - noise }
    public var context: String { bssid ?? ssid ?? "unidentified" }
    public var networkIdentity: String { ssid ?? bssid ?? "unidentified" }
    public init(ssid: String? = nil, bssid: String? = nil, rssi: Double? = nil, noise: Double? = nil, linkRate: Double? = nil, channel: Int? = nil, band: String? = nil, connected: Bool = false) {
        self.ssid = ssid; self.bssid = bssid; self.rssi = rssi; self.noise = noise; self.linkRate = linkRate; self.channel = channel; self.band = band; self.connected = connected
    }
}
public struct SpeedResult: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var download: Double?
    public var upload: Double?
    public var latency: Double?
    public var jitter: Double?
    public var bytes: Int = 0
    public var note: String = ""
    public var network: String = ""
    public var route: String = ""
    public var trace: [RateSample]?
    public init() {}
}
public struct MapPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = min(1, max(0, x)); self.y = min(1, max(0, y)) }
}
public struct Room: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var origin: MapPoint
    public var width: Double
    public var height: Double
    public init(name: String, origin: MapPoint, width: Double, height: Double) { self.name = name; self.origin = origin; self.width = width; self.height = height }
    public func contains(_ p: MapPoint) -> Bool { p.x >= origin.x && p.x <= origin.x + width && p.y >= origin.y && p.y <= origin.y + height }
}
public struct SurveyPoint: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var position: MapPoint
    public var readings: [Reading]
    public var speed: SpeedResult?
    public var date = Date()
    public init(name: String, position: MapPoint, readings: [Reading], speed: SpeedResult? = nil) { self.name = name; self.position = position; self.readings = readings; self.speed = speed }
    public var meanSignal: Double? { Statistics.mean(readings.compactMap(\.rssi)) }
    public var variability: Double? { Statistics.deviation(readings.compactMap(\.rssi)) }
    public func value(_ layer: HeatLayer) -> Double? {
        switch layer { case .signal: return meanSignal; case .download: return speed?.download; case .upload: return speed?.upload; case .latency: return speed?.latency }
    }
}
public struct SurveySession: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var date = Date()
    public var points: [SurveyPoint] = []
    public var layoutSnapshot: LayoutSnapshot?
    public var plannedSpots: [PlannedSpot]?
    public var profile: String?
    public init(name: String) { self.name = name }
}
public struct Floor: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var imageData: Data?
    public var aspect: Double = 1.5
    public var rooms: [Room] = []
    public var routers: [RouterMarker]?
    public var doors: [DoorMarker]?
    public var sessions: [SurveySession] = [SurveySession(name: "Survey 1")]
    public init(name: String) { self.name = name }
}
public struct Space: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var floors: [Floor] = [Floor(name: "Main floor")]
    public init(name: String) { self.name = name }
}
public struct ConnectionEvent: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var message: String
    public init(_ message: String) { self.message = message }
}
public struct Archive: Codable {
    public var version = 2
    public var spaces: [Space] = []
    public var tests: [SpeedResult] = []
    public var history: [Reading] = []
    public var events: [ConnectionEvent] = []
    public init() {}
}
public enum HeatLayer: String, CaseIterable, Codable, Identifiable {
    case signal = "Signal", download = "Download", upload = "Upload", latency = "Latency"
    public var id: String { rawValue }
    public var unit: String { self == .signal ? "dBm" : self == .latency ? "ms" : "Mbps" }
    public func quality(_ value: Double) -> Double {
        let q: Double
        switch self { case .signal: q = (Strength.score(value) ?? 0) / 100; case .download: q = value / 100; case .upload: q = value / 40; case .latency: q = 1 - value / 150 }
        return min(1, max(0, q))
    }
}
public enum Statistics {
    public static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
    public static func deviation(_ xs: [Double]) -> Double? { guard let m = mean(xs) else { return nil }; return sqrt(xs.reduce(0) { $0 + pow($1 - m, 2) } / Double(xs.count)) }
    public static func mbps(bytes: Int, seconds: Double) -> Double? { guard bytes >= 0, seconds > 0 else { return nil }; return Double(bytes) * 8 / seconds / 1_000_000 }
    public static func estimate(at p: MapPoint, points: [SurveyPoint], rooms: [Room], layer: HeatLayer) -> Double? {
        let room = rooms.first { $0.contains(p) }
        if !rooms.isEmpty && room == nil { return nil }
        let candidates = points.compactMap { sample -> (Double, Double)? in
            guard room == nil || room!.contains(sample.position), let value = sample.value(layer) else { return nil }
            let sx = room?.width ?? 1, sy = room?.height ?? 1
            return (hypot((p.x - sample.position.x) / max(sx, 0.001), (p.y - sample.position.y) / max(sy, 0.001)), value)
        }.sorted { $0.0 < $1.0 }
        guard let nearest = candidates.first, nearest.0 <= 0.6 else { return nil }
        if nearest.0 < 0.015 { return nearest.1 }
        guard candidates.count >= 3 else { return nil }
        let local = candidates.filter { $0.0 <= 1.2 }
        guard local.count >= 3 else { return nil }
        let weighted = local.reduce((0.0, 0.0)) { acc, pair in let w = 1 / pow(max(pair.0, 0.001), 2); return (acc.0 + pair.1 * w, acc.1 + w) }
        return weighted.0 / weighted.1
    }
    public static func csv(_ session: SurveySession) -> String {
        func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let header = "name,date,x,y,signal_dbm,signal_stddev,download_mbps,upload_mbps,latency_ms,network"
        return ([header] + session.points.map { p in
            [escape(p.name), ISO8601DateFormatter().string(from: p.date), String(p.position.x), String(p.position.y), p.meanSignal.map(String.init(describing:)) ?? "", p.variability.map(String.init(describing:)) ?? "", p.speed?.download.map(String.init(describing:)) ?? "", p.speed?.upload.map(String.init(describing:)) ?? "", p.speed?.latency.map(String.init(describing:)) ?? "", escape(p.readings.first?.ssid ?? "Unknown")].joined(separator: ",")
        }).joined(separator: "\n")
    }
}

public enum Strength {
    public static func score(_ rssi: Double?) -> Double? { rssi.map { min(100, max(0, ($0 + 90) * 2)) } }
    public static func label(_ rssi: Double?) -> String {
        guard let s = score(rssi) else { return "Unavailable" }
        return s >= 75 ? "Excellent" : s >= 50 ? "Good" : s >= 30 ? "Fair" : "Weak"
    }
}
public struct RateSample: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var download: Double?
    public var upload: Double?
    public init(download: Double? = nil, upload: Double? = nil) { self.download = download; self.upload = upload }
}
public struct TestUpdate: Sendable {
    public var phase: String
    public var rate: Double?
    public var bytes: Int
    public init(phase: String, rate: Double?, bytes: Int) { self.phase = phase; self.rate = rate; self.bytes = bytes }
}
public struct CounterTracker {
    private var previous: (UInt64, UInt64, Double)?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func sample(received: UInt64, sent: UInt64, time: Double) -> RateSample {
        defer { previous = (received, sent, time) }
        guard let p = previous, time > p.2, received >= p.0, sent >= p.1 else { return RateSample() }
        let seconds = time - p.2
        return RateSample(download: Double(received - p.0) * 8 / seconds / 1_000_000, upload: Double(sent - p.1) * 8 / seconds / 1_000_000)
    }
}
public struct RouterMarker: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var position: MapPoint
    public init(name: String, position: MapPoint) { self.name = name; self.position = position }
}
public struct DoorMarker: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var position: MapPoint
    public init(position: MapPoint) { self.position = position }
}
public struct LayoutSnapshot: Codable, Sendable {
    public var rooms: [Room]
    public var routers: [RouterMarker]
    public var doors: [DoorMarker]
    public var imageData: Data?
    public var aspect: Double
    public init(_ floor: Floor) { rooms = floor.rooms; routers = floor.routers ?? []; doors = floor.doors ?? []; imageData = floor.imageData; aspect = floor.aspect }
    public func floor(name: String) -> Floor {
        var f = Floor(name: name); f.rooms = rooms; f.routers = routers; f.doors = doors; f.imageData = imageData; f.aspect = aspect; return f
    }
}
public struct PlannedSpot: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var position: MapPoint
    public var skipped = false
    public var completedPointID: UUID?
    public init(name: String, position: MapPoint) { self.name = name; self.position = position }
}
public enum SurveyPlanner {
    public static func spots(for floor: Floor) -> [PlannedSpot] {
        let router = floor.routers?.first?.position ?? MapPoint(x: 0.5, y: 0.5)
        let offsets = [(0.5,0.5),(0.18,0.18),(0.82,0.18),(0.82,0.82),(0.18,0.82)]
        return floor.rooms.flatMap { room in offsets.enumerated().map { i, offset in
            PlannedSpot(name: "\(room.name) · \(i == 0 ? "Center" : "Corner \(i)")", position: MapPoint(x: room.origin.x + room.width * offset.0, y: room.origin.y + room.height * offset.1))
        }}.sorted { hypot($0.position.x-router.x, $0.position.y-router.y) < hypot($1.position.x-router.x, $1.position.y-router.y) }
    }
}
public struct WidgetSnapshot: Codable, Sendable {
    public var date: Date
    public var network: String
    public var strength: Double?
    public var strengthLabel: String
    public var download: Double?
    public var upload: Double?
    public var testDate: Date?
    public var space: String
    public var completed: Int
    public var total: Int
    public init(date: Date = Date(), network: String, strength: Double?, strengthLabel: String, download: Double?, upload: Double?, testDate: Date?, space: String, completed: Int, total: Int) {
        self.date = date; self.network = network; self.strength = strength; self.strengthLabel = strengthLabel; self.download = download; self.upload = upload; self.testDate = testDate; self.space = space; self.completed = completed; self.total = total
    }
}
public enum Suitability {
    public static func guidance(_ test: SpeedResult?) -> String {
        guard let t = test, let down = t.download, let up = t.upload, let response = t.latency else { return "Run a complete speed test for call and gaming guidance." }
        let calls = down >= 10 && up >= 5 && response < 100
        let gaming = response < 50 && (t.jitter ?? .infinity) < 15
        return "Video calls: \(calls ? "looks suitable" : "may struggle"). Online gaming: \(gaming ? "promising response time" : "response may be inconsistent"). Based on measured speed and response only; packet loss and app performance are not measured."
    }
}

public extension SurveySession {
    var nextSpot: PlannedSpot? { plannedSpots?.first { !$0.skipped && $0.completedPointID == nil } }
}
