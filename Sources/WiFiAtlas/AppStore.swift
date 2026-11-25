import SwiftUI
import AppKit
import Network
import AtlasCore
import UserNotifications
import WidgetKit

@MainActor final class AppStore: ObservableObject {
    @Published var archive = Archive()
    @Published var current = Reading()
    @Published var connectionInfo = ConnectionInfoSnapshot()
    @Published var infoRefreshing = false
    private var lastInfoRefresh = Date.distantPast
    private var infoGeneration = UUID()
    @Published var live: [Reading] = []
    @Published var nearby: [NearbyNetwork] = []
    @Published var scanning = false
    @Published var testing = false
    @Published var surveying = false
    @Published var progress = 0.0
    @Published var testBytes = 0
    @Published var status = "Ready"
    @Published var error: String?
    @Published var route = "Checking route"
    @Published var selectedSpace: UUID?
    @Published var selectedFloor: UUID?
    @Published var selectedSession: UUID?
    @Published var captureProgress = 0
    @Published var awake = true
    let wifi = WiFiService()
    var speed = SpeedService()
    let trafficService = TrafficService()
    @Published var traffic = RateSample()
    @Published var trafficHistory: [RateSample] = []
    @Published var testTrace: [RateSample] = []
    @Published var testDownload: Double?
    @Published var testUpload: Double?
    @Published var testPhase = "Ready"
    @Published var surveyActive = false
    @Published var navigation = "Overview"
    private var capturedReadings: [Reading] = []
    private var weakSince: Date?
    private var lastAlert = Date.distantPast
    private var lastWidget = Date.distantPast
    private var lastWidgetReload = Date.distantPast
    var currentSpot: PlannedSpot? { session?.nextSpot }
    var surveyFinished: Bool { session?.plannedSpots != nil && currentSpot == nil }
    var displayFloor: Floor? { guard let floor else { return nil }; return session?.layoutSnapshot?.floor(name: floor.name) ?? floor }
    private var repository: LocalRepository?
    private var timer: Timer?
    private var saveTimer: Timer?
    private var speedTask: Task<SpeedResult?, Never>?
    private var surveyTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastHistory = Date.distantPast
    private var observations: [NSObjectProtocol] = []
    var floor: Floor? { archive.spaces.first(where: { $0.id == selectedSpace })?.floors.first(where: { $0.id == selectedFloor }) }
    var session: SurveySession? { floor?.sessions.first(where: { $0.id == selectedSession }) }
    init(preview: Bool = false) {
        if preview { return }
        do { let repo = try LocalRepository(); archive = try repo.load(); repository = repo }
        catch { self.error = "Could not open local storage. Changes cannot be saved: \(error.localizedDescription)" }
        selectSpace(archive.spaces.first?.id)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let route = path.status != .satisfied ? "Offline" : path.usesInterfaceType(.wiredEthernet) ? "Ethernet path — may bypass Wi-Fi" : path.usesInterfaceType(.other) ? "VPN / other path — routing may differ" : path.usesInterfaceType(.wifi) ? "Wi-Fi path (VPN routing may differ)" : "Other network path"
            Task { @MainActor in guard let self else { return }
                if self.testing && self.route != "Checking route" && self.route != route { self.cancelTest(); self.error = "Connection route changed. Please retry the test." }
                self.route = route; self.refreshConnectionInfo() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "atlas.path", qos: .utility))
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.awake = false; self?.surveyActive = false; self?.trafficService.reset(); self?.cancelTest(); self?.cancelSurvey(); self?.save() } })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.awake = true; self?.sample() } })
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self, self.awake else { return }
            let visible = NSApp.isActive || PanelManager.shared.hasVisiblePanels || self.surveyActive || self.testing
            if visible || Date().timeIntervalSince(self.current.date) >= 10 { self.sample() }
        } }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.save() } }
    }
    func refreshConnectionInfo() {
        guard !infoRefreshing else { return }
        infoRefreshing = true; lastInfoRefresh = Date()
        let interface = trafficService.wifiInterface, generation = UUID(); infoGeneration = generation
        Task {
            let info = await Task.detached(priority: .utility) { ConnectionInfoService.read(interface: interface) }.value
            guard infoGeneration == generation else { return }
            connectionInfo = info; infoRefreshing = false
        }
    }
    func save() {
        let days = max(1, UserDefaults.standard.integer(forKey: "retentionDays") == 0 ? 7 : UserDefaults.standard.integer(forKey: "retentionDays"))
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        archive.history.removeAll { $0.date < cutoff }
        do { try repository?.save(archive); publishWidget() } catch { self.error = "Saving failed: \(error.localizedDescription)" }
    }
    func sample() {
        let next = wifi.read()
        if next.networkIdentity != current.networkIdentity || next.connected != current.connected {
            connectionInfo = ConnectionInfoSnapshot(); lastInfoRefresh = .distantPast; infoGeneration = UUID(); infoRefreshing = false
        }
        if !live.isEmpty && (next.connected != current.connected || next.networkIdentity != current.networkIdentity) {
            archive.events.insert(ConnectionEvent(next.connected ? "Connected: \(next.ssid ?? "unidentified Wi-Fi")" : "Wi-Fi disconnected"), at: 0)
            if testing { cancelTest(); error = "Connection changed. The speed test was discarded." }
        }
        if surveyActive && !next.connected { surveyActive = false; cancelSurvey(); error = "Wi-Fi disconnected. Your completed spots are saved; resume when connected." }
        if next.connected && current.connected && next.networkIdentity == current.networkIdentity, let before = current.bssid, let after = next.bssid, before != after {
            archive.events.insert(ConnectionEvent("Switched access point on \(next.ssid ?? "your Wi-Fi network")"), at: 0)
        }
        current = next; live.append(next)
        if Date().timeIntervalSince(lastInfoRefresh) >= 15 { refreshConnectionInfo() }
        if surveying { capturedReadings.append(next) }
        let selected = UserDefaults.standard.string(forKey: "trafficInterface") ?? "Wi-Fi"
        if selected == "Wi-Fi" && !next.connected { trafficService.reset(); traffic = RateSample() }
        else { traffic = trafficService.sample(interface: selected == "Wi-Fi" ? trafficService.wifiInterface : selected) }
        trafficHistory.append(traffic)
        if trafficHistory.count > 120 { trafficHistory.removeFirst(trafficHistory.count - 120) }
        checkAlerts()
        if Date().timeIntervalSince(lastWidget) > 60 { publishWidget(); lastWidget = Date() }
        if live.count > 300 { live.removeFirst(live.count - 300) }
        if Date().timeIntervalSince(lastHistory) >= 60 { archive.history.append(next); lastHistory = Date() }
    }
    func selectSpace(_ id: UUID?) { selectedSpace = id; selectFloor(archive.spaces.first(where: { $0.id == id })?.floors.first?.id) }
    func selectFloor(_ id: UUID?) { selectedFloor = id; selectedSession = floor?.sessions.last?.id }
    func newSpace(_ name: String) { let space = Space(name: name); archive.spaces.append(space); selectSpace(space.id); save() }
    func newFloor(_ name: String) {
        guard let s = archive.spaces.firstIndex(where: { $0.id == selectedSpace }) else { return }
        let floor = Floor(name: name); archive.spaces[s].floors.append(floor); selectFloor(floor.id); save()
    }
    func editFloor(_ change: (inout Floor) -> Void) {
        guard let s = archive.spaces.firstIndex(where: { $0.id == selectedSpace }), let f = archive.spaces[s].floors.firstIndex(where: { $0.id == selectedFloor }) else { return }
        change(&archive.spaces[s].floors[f]); save()
    }
    func editSession(_ change: (inout SurveySession) -> Void) { let id = selectedSession; editFloor { floor in if let i = floor.sessions.firstIndex(where: { $0.id == id }) { change(&floor.sessions[i]) } } }
    func newSession() { let session = SurveySession(name: "Survey \((floor?.sessions.count ?? 0) + 1)"); editFloor { $0.sessions.append(session) }; selectedSession = session.id }
    func scan() {
        guard !scanning, !testing, !surveying else { return }; scanning = true
        Task { do { nearby = try await wifi.scan() } catch { self.error = "Scan failed: \(error.localizedDescription)" }; scanning = false }
    }
    @discardableResult func startTest(quick: Bool = false) -> Task<SpeedResult?, Never>? {
        guard !testing, !scanning, UserDefaults.standard.bool(forKey: "speedConsent") else { return nil }
        testing = true; progress = 0; testBytes = 0; testDownload = nil; testUpload = nil; testTrace = []; testPhase = "Response time"
        speed = SpeedService(byteBudget: quick ? 50_000_000 : 250_000_000, duration: quick ? 20 : 30, phaseDuration: quick ? 5 : 9)
        speed.onUpdate = { [weak self] update in
            guard let self else { return }
            self.testPhase = update.phase; self.testBytes = update.bytes
            if update.phase == "Download" { self.testDownload = update.rate } else { self.testUpload = update.rate }
            self.testTrace.append(RateSample(download: update.phase == "Download" ? update.rate : nil, upload: update.phase == "Upload" ? update.rate : nil))
            if self.testTrace.count > 240 { self.testTrace.removeFirst() }
        }
        let network = current.networkIdentity, initialRoute = route
        let task = Task<SpeedResult?, Never> { [self] in
            defer { testing = false; speedTask = nil }
            do {
                var result = try await speed.run(network: network, route: initialRoute) { [weak self] phase, fraction, bytes in self?.status = phase; self?.progress = fraction; self?.testBytes = bytes }
                try Task.checkCancellation()
                guard wifi.read().networkIdentity == network, route == initialRoute else { error = "Network or route changed. Test discarded."; return nil }
                result.trace = testTrace; archive.tests.insert(result, at: 0); save(); status = "Test complete"; progress = 1; testBytes = result.bytes
                return result
            } catch { if !Task.isCancelled { self.error = "Speed test failed: \(error.localizedDescription)" }; status = "Test stopped"; return nil }
        }
        speedTask = task; return task
    }
    func cancelTest() { speedTask?.cancel(); speed.cancel() }
    func capture(at position: MapPoint, name: String, includeSpeed: Bool = true) {
        guard !surveying, !testing, !scanning, current.connected, selectedSession != nil else { return }
        if let network = session?.points.first?.readings.first?.networkIdentity, network != wifi.read().networkIdentity {
            error = "This survey belongs to another Wi-Fi network. Start a new survey for this network."; return
        }
        surveying = true; surveyActive = true; captureProgress = 0; capturedReadings = [wifi.read()]
        let sessionID = selectedSession, floorID = selectedFloor, spaceID = selectedSpace
        let spotID = currentSpot?.id
        surveyTask = Task {
            defer { surveying = false; surveyTask = nil }
            do {
                for i in 0..<3 { try Task.checkCancellation(); captureProgress = i + 1; try await Task.sleep(for: .seconds(1)) }
                var result: SpeedResult?
                if includeSpeed, let task = startTest(quick: session?.profile == "Quick") { result = await task.value }
                try Task.checkCancellation()
                guard selectedSession == sessionID, selectedFloor == floorID, selectedSpace == spaceID else { return }
                guard !includeSpeed || result != nil else { error = "This spot was not completed. Stay here and retry, or skip it."; return }
                let valid = capturedReadings.filter { $0.connected }
                guard !valid.isEmpty, Set(valid.map(\.networkIdentity)).count == 1 else { error = "Wi-Fi changed during this measurement. Please retry."; return }
                let point = SurveyPoint(name: name, position: position, readings: valid, speed: result)
                editSession { session in
                    session.points.append(point)
                    if let i = session.plannedSpots?.firstIndex(where: { $0.id == spotID }) { session.plannedSpots?[i].completedPointID = point.id }
                }
                if currentSpot == nil { surveyActive = false }
            } catch { }
        }
    }
    func beginSurvey(profile: String) {
        guard let floor, !floor.rooms.isEmpty, !(floor.routers ?? []).isEmpty else { error = "Add rooms and at least one router first."; return }
        var session = SurveySession(name: "Survey \(floor.sessions.count + 1)")
        session.layoutSnapshot = LayoutSnapshot(floor); session.plannedSpots = SurveyPlanner.spots(for: floor); session.profile = profile
        editFloor { $0.sessions.append(session) }; selectedSession = session.id; surveyActive = current.connected
    }
    func resumeSurvey() { guard current.connected else { error = "Connect to Wi-Fi before resuming."; return }; surveyActive = true }
    func pauseSurvey() { surveyActive = false; cancelSurvey(); save() }
    func skipSpot() { guard !surveying, let id = currentSpot?.id else { return }; editSession { s in if let i = s.plannedSpots?.firstIndex(where: { $0.id == id }) { s.plannedSpots?[i].skipped = true } }; if currentSpot == nil { surveyActive = false } }
    func duplicateSpace() {
        guard let original = archive.spaces.first(where: { $0.id == selectedSpace }) else { return }
        var space = Space(name: original.name + " copy")
        space.floors = original.floors.map { old in var f = Floor(name: old.name); f.rooms = old.rooms; f.routers = old.routers; f.doors = old.doors; f.imageData = old.imageData; f.aspect = old.aspect; return f }
        archive.spaces.append(space); selectSpace(space.id); save()
    }
    func publishWidget() {
        let snapshot = WidgetSnapshot(network: current.ssid ?? (current.connected ? "Wi-Fi connected" : "Disconnected"), strength: Strength.score(current.rssi), strengthLabel: Strength.label(current.rssi), download: archive.tests.first?.download, upload: archive.tests.first?.upload, testDate: archive.tests.first?.date, space: archive.spaces.first(where: { $0.id == selectedSpace })?.name ?? "No layout", completed: session?.points.count ?? 0, total: session?.plannedSpots?.count ?? 0)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AtlasAppGroup") as? String, !group.contains("$("), let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        do { try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("widget.json"), options: .atomic); if Date().timeIntervalSince(lastWidgetReload) >= 60 { WidgetCenter.shared.reloadAllTimelines(); lastWidgetReload = Date() } } catch { NSLog("Widget snapshot failed: %@", error.localizedDescription) }
    }
    func enableAlerts() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in UserDefaults.standard.set(allowed, forKey: "connectionAlerts") }
    }
    private func checkAlerts() {
        guard UserDefaults.standard.bool(forKey: "connectionAlerts") else { return }
        if !current.connected || (Strength.score(current.rssi) ?? 100) < 30 { if weakSince == nil { weakSince = Date() } } else { weakSince = nil }
        guard let since = weakSince, Date().timeIntervalSince(since) > (current.connected ? 30 : 5), Date().timeIntervalSince(lastAlert) > 600 else { return }
        lastAlert = Date()
        let content = UNMutableNotificationContent(); content.title = current.connected ? "Your Wi-Fi signal is weak" : "Wi-Fi disconnected"; content.body = current.connected ? "Try a location closer to your router, or compare your saved room measurements." : "Check your network connection."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func cancelSurvey() { surveyTask?.cancel(); if surveying { cancelTest() } }
    func clearHistory() { archive.history = []; archive.tests = []; archive.events = []; live = []; save() }
}
