import SwiftUI
import AppKit
import Charts
import AtlasCore

typealias ViewState<Value> = SwiftUI.State<Value>

@main struct WiFiAtlasApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("menuEnabled") private var menuEnabled = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            AppPreview.render(to: CommandLine.arguments[index+1]); exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("WiFi Atlas", id: "main") {
            RootView().environmentObject(store).frame(minWidth: 940, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.save() }
        }.defaultSize(width: 1220, height: 860)
        .handlesExternalEvents(matching: ["*"])
        .commands { CommandGroup(after: .newItem) { Button("New layout") { store.newSpace("My layout"); store.navigation = "Layouts" }.keyboardShortcut("n", modifiers: [.command, .shift]) } }
        Settings { SettingsView().environmentObject(store).modifier(AtlasAppearance()) }
        MenuBarExtra(isInserted: $menuEnabled) { MenuPanel().environmentObject(store).modifier(AtlasAppearance()) } label: { MenuLabel().environmentObject(store) }.menuBarExtraStyle(.window)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { PanelManager.shared.prepareForTermination(); return .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct AtlasAppearance: ViewModifier {
    @AppStorage("appearance") var appearance = "System"
    @AppStorage("accent") var accent = "Blue"
    func body(content: Content) -> some View { content.tint(accent == "Green" ? .green : accent == "Purple" ? .purple : accent == "Orange" ? .orange : .blue).preferredColorScheme(appearance == "Light" ? .light : appearance == "Dark" ? .dark : nil) }
}
enum Page: String, CaseIterable, Identifiable {
    case dashboard = "Overview", survey = "Layouts", speed = "Speed test", history = "History", diagnostics = "Connection tools"
    var id: String { rawValue }
    var icon: String { switch self { case .dashboard: "square.grid.2x2"; case .survey: "map"; case .speed: "speedometer"; case .history: "clock.arrow.circlepath"; case .diagnostics: "waveform.path.ecg" } }
}
struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) { Image(systemName: "wifi").font(.title).foregroundStyle(.tint); VStack(alignment: .leading) { Text("WiFi Atlas").font(.headline); Text("Find your best connection").font(.caption2).foregroundStyle(.secondary) } }.padding(.horizontal, 14).padding(.top, 20)
                List(Page.allCases, selection: Binding(get: { Page(rawValue: store.navigation) }, set: { store.navigation = $0?.rawValue ?? "Overview" })) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) { Label(store.current.connected ? "Connected" : "Disconnected", systemImage: store.current.connected ? "wifi" : "wifi.slash"); Text(store.current.ssid ?? "Network name unavailable").font(.caption).foregroundStyle(.secondary); SettingsLink { Label("Settings", systemImage: "gearshape") } }.padding()
            }.navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 270)
        } detail: {
            Group { switch Page(rawValue: store.navigation) ?? .dashboard { case .dashboard: DashboardView(); case .survey: SurveyView(); case .speed: SpeedView(); case .history: HistoryView(); case .diagnostics: DiagnosticsView() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
                .toolbar { ToolbarItem { Text(store.navigation).font(.headline) }; ToolbarItem { Menu { ForEach(PanelKind.allCases) { kind in Button(kind.rawValue) { PanelManager.shared.show(kind, store: store) } } } label: { Label("Floating panels", systemImage: "macwindow.on.rectangle") } }; ToolbarItem { SettingsLink { Image(systemName: "slider.horizontal.3") } } }
        }.modifier(AtlasAppearance())
        .onAppear { PanelManager.shared.restore(store: store) }
        .onOpenURL { url in store.navigation = url.host == "survey" ? "Layouts" : url.host == "speed" ? "Speed test" : "Overview"; NSApp.activate(ignoringOtherApps: true) }
        .alert("WiFi Atlas", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct Card<Content: View>: View {
    @AppStorage("dense") var dense = false
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: dense ? 10 : 18) { content }.padding(dense ? 14 : 22).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.07), lineWidth: 1) } }
}
func number(_ value: Double?, digits: Int = 0) -> String { value.map { String(format: "%.*f", digits, $0) } ?? "—" }
struct Metric: View {
    let title: String; let value: String; let unit: String; let icon: String
    var body: some View { Card { Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary); HStack(alignment: .firstTextBaseline, spacing: 5) { Text(value).font(.system(size: 32, weight: .semibold)).monospacedDigit(); Text(unit).font(.caption).foregroundStyle(.secondary) } } }
}
struct DialMeter: View {
    let title: String
    let value: Double?
    var maximum: Double = 100
    var unit = "Mbps"
    var subtitle = ""
    var color: Color = .blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fraction: Double { min(1, max(0, (value ?? 0) / maximum)) }
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.headline)
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: 105), radius = min(size.width / 2 - 20, 86)
                    func arc(_ end: Double) -> Path { var p = Path(); p.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(135 + end * 270), clockwise: false); return p }
                    context.stroke(arc(1), with: .color(.secondary.opacity(0.13)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    if value != nil { context.stroke(arc(fraction), with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round)) }
                    for tick in 0...10 { let angle = (135 + Double(tick) * 27) * .pi / 180; var p = Path(); p.move(to: CGPoint(x: center.x + cos(angle) * (radius-13), y: center.y + sin(angle) * (radius-13))); p.addLine(to: CGPoint(x: center.x + cos(angle) * (radius-19), y: center.y + sin(angle) * (radius-19))); context.stroke(p, with: .color(.secondary.opacity(0.5)), lineWidth: 1) }
                }
                VStack(spacing: 3) { Text(number(value, digits: unit == "Mbps" ? 1 : 0)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText()); Text(unit).font(.caption).foregroundStyle(.secondary) }.offset(y: 13)
            }.frame(height: 176)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30)
        }.frame(maxWidth: .infinity).animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value).accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(number(value, digits: 1)) \(unit), \(subtitle)")
    }
}
struct SignalChart: View {
    let readings: [Reading]
    var body: some View { Chart(readings) { r in if let score = Strength.score(r.rssi) { LineMark(x: .value("Time", r.date), y: .value("Strength", score)).interpolationMethod(.linear).foregroundStyle(.blue) } }.chartYScale(domain: 0...100).frame(height: 160).accessibilityLabel("Wi-Fi strength over time, estimated score out of 100") }
}
struct RateChart: View {
    let samples: [RateSample]
    var body: some View { Chart(samples) { s in if let d = s.download { LineMark(x: .value("Time", s.date), y: .value("Mbps", d), series: .value("Direction", "Download")).foregroundStyle(by: .value("Direction", "Download")) }; if let u = s.upload { LineMark(x: .value("Time", s.date), y: .value("Mbps", u), series: .value("Direction", "Upload")).foregroundStyle(by: .value("Direction", "Upload")) } }.chartForegroundStyleScale(["Download": Color.blue, "Upload": Color.purple]).frame(height: 150).accessibilityLabel("Download and upload speed over time in Mbps") }
}
struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("showSignal") var showSignal = true
    @AppStorage("showDetails") var showDetails = true
    @AppStorage("detailsFirst") var detailsFirst = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            HStack { VStack(alignment: .leading, spacing: 7) { Text(store.current.ssid ?? "Your connection, at a glance.").font(.largeTitle.weight(.semibold)); Text("\(Strength.label(store.current.rssi)) Wi-Fi signal · live network activity below").foregroundStyle(.secondary) }; Spacer(); Button("Test internet speed") { store.navigation = "Speed test" }.buttonStyle(.borderedProminent) }
            Card { HStack(spacing: 18) { DialMeter(title: "Wi-Fi strength", value: Strength.score(store.current.rssi), unit: "/ 100", subtitle: Strength.label(store.current.rssi), color: .green); DialMeter(title: "Downloading now", value: store.traffic.download, maximum: scale(store.traffic.download), subtitle: "Live activity · not available capacity"); DialMeter(title: "Uploading now", value: store.traffic.upload, maximum: scale(store.traffic.upload), subtitle: "Live activity · includes local traffic", color: .purple) } }
            if detailsFirst && showDetails { connectionDetails }
            Card { Text("Live network activity").font(.headline); RateChart(samples: store.trafficHistory); Text("Traffic through \(trafficInterface). A quiet connection can show zero even when fast internet is available.").font(.caption).foregroundStyle(.secondary) }
            if showSignal { Card { Text("Wi-Fi strength over time").font(.headline); SignalChart(readings: store.live) } }
            if !detailsFirst && showDetails { connectionDetails }
            Card { Text("What works well here?").font(.headline); Text(Suitability.guidance(store.archive.tests.first)).foregroundStyle(.secondary); if let t = store.archive.tests.first { Text("Based on your test from \(t.date.formatted()) · \(t.network.isEmpty ? "network unavailable" : t.network).").font(.caption).foregroundStyle(.secondary) }; Button("Compare rooms in your layout") { store.navigation = "Layouts" } }
        }.padding(28) }
    }
    var trafficInterface: String { let selected = UserDefaults.standard.string(forKey: "trafficInterface") ?? "Wi-Fi"; return selected == "Wi-Fi" ? "Wi-Fi (\(store.trafficService.wifiInterface))" : selected }
    var connectionDetails: some View { DisclosureGroup("Connection details · IP, router, DNS & Wi-Fi") { ConnectionInfoView().padding(.top, 14) } }

}
func scale(_ value: Double?) -> Double { let v = value ?? 0; return v <= 100 ? 100 : v <= 500 ? 500 : v <= 1000 ? 1000 : max(2000, ceil(v / 1000) * 1000) }
struct SpeedButton: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("speedConsent") var consent = false
    @ViewState var showingConsent = false
    var body: some View {
        Button { if store.testing { store.cancelTest() } else if consent { store.startTest() } else { showingConsent = true } } label: { Label(store.testing ? "Stop test" : "Start speed test", systemImage: store.testing ? "stop.fill" : "play.fill") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.scanning || store.surveying)
        .alert("Start an internet speed test?", isPresented: $showingConsent) { Button("Cancel", role: .cancel) {}; Button("Allow and start") { consent = true; store.startTest() } } message: { Text("Tests send traffic to Cloudflare, which receives your IP address. Each test uses up to 250 MB of payload data and 30 seconds. Results stay on this Mac; tests run only when requested.") }
    }
}
struct SpeedView: View {
    @EnvironmentObject var store: AppStore
    var result: SpeedResult? { store.archive.tests.first }
    var down: Double? { store.testing ? store.testDownload : result?.download }
    var up: Double? { store.testing ? store.testUpload : result?.upload }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) { Text("How fast is your internet?").font(.largeTitle.weight(.semibold)); Text("A live test of your connection to Cloudflare. Keep your Mac still and pause large downloads for a clearer result.").foregroundStyle(.secondary) }
        Card { HStack(spacing: 18) { DialMeter(title: "Wi-Fi strength", value: Strength.score(store.current.rssi), unit: "/ 100", subtitle: Strength.label(store.current.rssi), color: .green); DialMeter(title: "Download", value: down, maximum: scale(down), subtitle: store.testing ? (store.testPhase == "Download" ? "Measuring now" : "Waiting / completed phase") : "Last tested speed"); DialMeter(title: "Upload", value: up, maximum: scale(up), subtitle: store.testing ? (store.testPhase == "Upload" ? "Measuring now" : "Waiting / completed phase") : "Last tested speed", color: .purple) }; Divider(); HStack { VStack(alignment: .leading) { Text(store.testing ? store.status : result == nil ? "Ready when you are" : "Last test: \(result!.date.formatted())").font(.headline); Text(store.testing ? "\(number(Double(store.testBytes) / 1_000_000, digits: 1)) MB used" : "Network: \(result?.network ?? "not tested") · No background speed tests").font(.caption).foregroundStyle(.secondary) }; Spacer(); SpeedButton() }; if store.testing { ProgressView(value: store.progress) } }
        Card { Text(store.testing ? "Test in progress · Mbps" : "Last test · Mbps").font(.headline); RateChart(samples: store.testing ? store.testTrace : result?.trace ?? []); Text(store.route).font(.caption).foregroundStyle(.secondary) }
        HStack { Metric(title: "Response time", value: number(store.testing ? nil : result?.latency), unit: "ms", icon: "timer"); Metric(title: "Consistency", value: number(store.testing ? nil : result?.jitter), unit: "ms variation", icon: "waveform.path") }
        Card { Text("What do these mean?").font(.headline); Text("Download is how quickly you receive files and video. Upload is how quickly you send files and your camera feed. Lower response time and smaller variation generally feel smoother.").foregroundStyle(.secondary); Text(Suitability.guidance(result)); if let note = result?.note, !note.isEmpty { Text(note).foregroundStyle(.orange) }; Text("Response is measured with web requests, not a ping. Available speed differs from the live activity shown on Overview.").font(.caption).foregroundStyle(.secondary) }
    }.padding(28) } }
}
struct DiagnosticsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { ScrollView { VStack(alignment: .leading,spacing: 22) {
        Text("Understand your connection.").font(.largeTitle.weight(.semibold))
        Card { ConnectionInfoView() }
        Card {
            Text("Nearby Wi-Fi networks").font(.headline)
            HStack { Button("Allow network names") { store.wifi.requestPermission() }; Button(store.scanning ? "Looking…" : "Find nearby networks") { store.scan() }.disabled(store.scanning || store.testing || store.surveyActive); if store.scanning { ProgressView().controlSize(.small) } }
            Text("A scan can briefly affect connectivity. Many networks on a channel can suggest crowding, but this does not measure how busy it actually is.").font(.caption).foregroundStyle(.secondary)
            Table(store.nearby) { TableColumn("Network",value: \.name); TableColumn("Band",value: \.band); TableColumn("Channel") { Text(String($0.channel)) }; TableColumn("Strength") { Text(Strength.label(Double($0.signal))) }; TableColumn("Security",value: \.security) }.frame(height: 240).overlay { if store.nearby.isEmpty && !store.scanning { ContentUnavailableView("No networks listed yet",systemImage: "wifi",description: Text("Allow network names, then look for nearby networks.")) } }
        }
    }.padding(28) } }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @ViewState var confirmDelete = false
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 22) {
        HStack { Text("Your connection history").font(.largeTitle.weight(.semibold)); Spacer(); Button("Clear history", role: .destructive) { confirmDelete = true } }
        Card { Text("Wi-Fi strength").font(.headline); SignalChart(readings: Array(store.archive.history.suffix(1440))); Text("One sample per minute while the app is awake; up to 24 hours shown.").font(.caption).foregroundStyle(.secondary) }
        Card { Text("Internet speed tests").font(.headline); Chart(store.archive.tests) { t in if let d = t.download { PointMark(x: .value("Time", t.date), y: .value("Mbps", d)).foregroundStyle(by: .value("Direction", "Download")) }; if let u = t.upload { PointMark(x: .value("Time", t.date), y: .value("Mbps", u)).foregroundStyle(by: .value("Direction", "Upload")) } }.frame(height: 150); ForEach(store.archive.tests.prefix(30)) { t in HStack { Text(t.date.formatted()); Spacer(); Text("↓ \(number(t.download, digits: 1))  ↑ \(number(t.upload, digits: 1)) Mbps"); Text("Response \(number(t.latency)) ms").foregroundStyle(.secondary) }.font(.caption) } }
        Card { Text("Connection changes").font(.headline); ForEach(store.archive.events.prefix(100)) { event in HStack { Text(event.message); Spacer(); Text(event.date.formatted()).foregroundStyle(.secondary) }.font(.caption) } }
    }.padding(28) }.confirmationDialog("Delete history and speed tests? Saved surveys will stay.", isPresented: $confirmDelete) { Button("Delete history", role: .destructive) { store.clearHistory() } } }
}
struct MenuLabel: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("menuStyle") var style = "Strength"
    @AppStorage("activityUnits") var units = "Mbps"
    @AppStorage("menuOrder") var order = "Download first"
    var body: some View { HStack(spacing: 4) { Image(systemName: store.current.connected ? "wifi" : "wifi.slash"); if style == "Strength" { Text("\(number(Strength.score(store.current.rssi)))%").monospacedDigit() }; if style == "Activity" { Text(activityLabel).monospacedDigit() }; if style == "Sparkline" { Image(nsImage: Sparkline.image(store.trafficHistory)).accessibilityLabel("Recent download activity") } } }
    var activityLabel: String { let d = activity(store.traffic.download), u = activity(store.traffic.upload); return order == "Upload first" ? "↑\(u) ↓\(d)" : "↓\(d) ↑\(u)" }
    func activity(_ x: Double?) -> String { "\(number(x.map { units == "MB/s" ? $0 / 8 : $0 }, digits: 1)) \(units)" }
}
struct MenuPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) var openWindow
    @AppStorage("menuShowGraph") var graph = true
    @AppStorage("menuShowStrength") var strength = true
    var body: some View { VStack(alignment: .leading, spacing: 14) { Label("WiFi Atlas", systemImage: "wifi").font(.headline); Text(store.current.ssid ?? "Your connection").foregroundStyle(.secondary); if strength { HStack { Text("Wi-Fi strength"); Spacer(); Text("\(Strength.label(store.current.rssi)) · \(number(Strength.score(store.current.rssi)))%").monospacedDigit() } }; Text("Live ↓ \(number(store.traffic.download, digits: 1))  ↑ \(number(store.traffic.upload, digits: 1)) Mbps").monospacedDigit(); if graph { RateChart(samples: Array(store.trafficHistory.suffix(60))).frame(height: 120) }; if store.testing { Text(store.status).font(.caption); ProgressView(value: store.progress) }; SpeedButton(); Divider(); Button("Open dashboard") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }; Menu("Floating panels") { ForEach(PanelKind.allCases) { kind in Button(kind.rawValue) { PanelManager.shared.show(kind, store: store) } } }; SettingsLink { Text("Settings…") }; Button("Quit WiFi Atlas") { store.save(); NSApp.terminate(nil) } }.padding(20).frame(width: 360) }
}
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appearance") var appearance = "System"
    @AppStorage("accent") var accent = "Blue"
    @AppStorage("dense") var dense = false
    @AppStorage("showSignal") var showSignal = true
    @AppStorage("showDetails") var showDetails = true
    @AppStorage("detailsFirst") var detailsFirst = false
    @AppStorage("menuEnabled") var menuEnabled = true
    @AppStorage("menuStyle") var menuStyle = "Strength"
    @AppStorage("menuOrder") var menuOrder = "Download first"
    @AppStorage("activityUnits") var units = "Mbps"
    @AppStorage("menuShowGraph") var graph = true
    @AppStorage("menuShowStrength") var strength = true
    @AppStorage("panelOnTop") var onTop = false
    @AppStorage("panelOpacity") var opacity = 1.0
    @AppStorage("speedConsent") var consent = false
    @AppStorage("retentionDays") var days = 7
    @AppStorage("trafficInterface") var trafficInterface = "Wi-Fi"
    @AppStorage("connectionAlerts") var alerts = false
    var body: some View { TabView {
        Form { Picker("Appearance", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }; Picker("Accent", selection: $accent) { ForEach(["Blue", "Green", "Purple", "Orange"], id: \.self) { Text($0) } }; Toggle("Compact spacing", isOn: $dense); Toggle("Show strength chart", isOn: $showSignal); Toggle("Show connection details", isOn: $showDetails); Toggle("Place details before charts", isOn: $detailsFirst); Button("Reset appearance") { appearance = "System"; accent = "Blue"; dense = false; showSignal = true; showDetails = true; detailsFirst = false } }.tabItem { Label("Appearance", systemImage: "paintpalette") }
        Form { Toggle("Show menu bar item", isOn: $menuEnabled); Picker("Menu bar style", selection: $menuStyle) { ForEach(["Icon only", "Strength", "Activity", "Sparkline"], id: \.self) { Text($0) } }; Picker("Activity units", selection: $units) { Text("Mbps").tag("Mbps"); Text("MB/s").tag("MB/s") }; Picker("Activity order", selection: $menuOrder) { Text("Download first").tag("Download first"); Text("Upload first").tag("Upload first") }; Toggle("Strength in popover", isOn: $strength); Toggle("Graph in popover", isOn: $graph); ForEach(PanelKind.allCases) { kind in Button("Open \(kind.rawValue.lowercased()) panel") { PanelManager.shared.show(kind, store: store) } }; Toggle("Keep panels on top", isOn: $onTop).onChange(of: onTop) { _, _ in PanelManager.shared.applySettings() }; Slider(value: $opacity, in: 0.4...1) { Text("Panel opacity") }.onChange(of: opacity) { _, _ in PanelManager.shared.applySettings() }; Text("System widgets are available in macOS Edit Widgets with the Xcode-built app and widget extension. They show timestamped summaries, not live traffic.").font(.caption).foregroundStyle(.secondary) }.tabItem { Label("Widgets", systemImage: "macwindow.on.rectangle") }
        Form { Picker("Activity interface", selection: $trafficInterface) { Text("Wi-Fi (automatic)").tag("Wi-Fi"); ForEach(store.trafficService.interfaces, id: \.self) { Text($0).tag($0) } }; Picker("Monitoring retention", selection: $days) { Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }.onChange(of: days) { _, _ in store.save() }; Toggle("Connection alerts", isOn: $alerts).onChange(of: alerts) { _, enabled in if enabled { store.enableAlerts() } }; Text("Alerts follow a disconnect lasting 5 seconds or weak signal lasting 30 seconds, with a 10-minute cooldown.").font(.caption).foregroundStyle(.secondary); Toggle("Allow manual Cloudflare speed tests", isOn: $consent); Text("Thorough tests use up to 250 MB and 30 seconds per spot. Surveys and results stay on this Mac. No automatic background speed tests.").font(.caption).foregroundStyle(.secondary); Button("Allow network names") { store.wifi.requestPermission() }; Button("Open Location Services") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) } }.tabItem { Label("Data & alerts", systemImage: "hand.raised") }
    }.formStyle(.grouped).padding().frame(width: 590, height: 640) }
}
