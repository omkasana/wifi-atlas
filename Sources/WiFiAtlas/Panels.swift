import SwiftUI
import AppKit
import AtlasCore

enum PanelKind: String, CaseIterable, Identifiable {
    case strength = "Wi-Fi strength", traffic = "Live activity", summary = "Connection summary", survey = "Survey progress"
    var id: String { rawValue }
}
@MainActor final class PanelManager: NSObject, NSWindowDelegate {
    static let shared = PanelManager()
    private var panels: [PanelKind: NSPanel] = [:]
    private var restored = false
    private var terminating = false
    var hasVisiblePanels: Bool { panels.values.contains { $0.isVisible } }
    func restore(store: AppStore) { guard !restored else { return }; restored = true; for raw in UserDefaults.standard.stringArray(forKey: "openPanels") ?? [] { if let kind = PanelKind(rawValue: raw) { show(kind, store: store) } } }
    func show(_ kind: PanelKind, store: AppStore) {
        if let panel = panels[kind] { panel.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 180, y: 220, width: 340, height: 300), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = kind.rawValue; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.delegate = self
        panel.contentMinSize = NSSize(width: 290, height: 240)
        panel.setFrameAutosaveName("AtlasPanel-" + kind.rawValue)
        panel.contentView = NSHostingView(rootView: FloatingPanelView(kind: kind).environmentObject(store).modifier(AtlasAppearance()))
        panels[kind] = panel; applySettings(); panel.makeKeyAndOrderFront(nil); persist()
    }
    func applySettings() { for panel in panels.values { panel.level = UserDefaults.standard.bool(forKey: "panelOnTop") ? .floating : .normal; let alpha = UserDefaults.standard.double(forKey: "panelOpacity"); panel.alphaValue = alpha == 0 ? 1 : max(0.4, min(1, alpha)) } }
    func prepareForTermination() { persist(); terminating = true }
    func windowWillClose(_ notification: Notification) { guard let window = notification.object as? NSWindow else { return }; panels = panels.filter { $0.value !== window }; if !terminating { persist() } }
    private func persist() { UserDefaults.standard.set(panels.keys.map(\.rawValue), forKey: "openPanels") }
}
struct FloatingPanelView: View {
    let kind: PanelKind
    @EnvironmentObject var store: AppStore
    var body: some View { VStack(alignment: .leading, spacing: 14) {
        switch kind {
        case .strength: DialMeter(title: "Wi-Fi strength", value: Strength.score(store.current.rssi), unit: "/ 100", subtitle: Strength.label(store.current.rssi), color: .green)
        case .traffic: Text("Live network activity").font(.headline); Text("↓ \(number(store.traffic.download, digits: 1))  ↑ \(number(store.traffic.upload, digits: 1)) Mbps").monospacedDigit(); RateChart(samples: store.trafficHistory); Text("Current traffic, not available speed").font(.caption).foregroundStyle(.secondary)
        case .summary: Label(store.current.ssid ?? "Your connection", systemImage: "wifi").font(.headline); Text("\(Strength.label(store.current.rssi)) signal"); Text(store.route).font(.caption).foregroundStyle(.secondary); if let t = store.archive.tests.first { Text("Last test ↓ \(number(t.download, digits: 1)) / ↑ \(number(t.upload, digits: 1)) Mbps"); Text(t.date.formatted()).font(.caption) }; Text(Suitability.guidance(store.archive.tests.first)).font(.caption)
        case .survey: Text(store.floor?.name ?? "No layout selected").font(.headline); Text(store.currentSpot?.name ?? (store.surveyFinished ? "Survey complete" : "Create a guided survey to begin")); ProgressView(value: Double(store.session?.points.count ?? 0), total: Double(max(1, store.session?.plannedSpots?.count ?? 1))); Text(store.surveying ? store.status : store.surveyActive ? "Move to the highlighted spot in Layouts." : "Survey paused").font(.caption); if store.surveyActive { Button("Pause") { store.pauseSurvey() } }
        }
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
}
enum Sparkline {
    @MainActor static func image(_ samples: [RateSample]) -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 16)); image.lockFocus()
        let values = Array(samples.suffix(24)).map { $0.download ?? 0 }, top = max(1, values.max() ?? 1)
        let path = NSBezierPath(); path.lineWidth = 1.2
        for (i, v) in values.enumerated() { let p = NSPoint(x: Double(i) / Double(max(1, values.count-1)) * 40 + 1, y: v / top * 13 + 1); if i == 0 { path.move(to: p) } else { path.line(to: p) } }
        NSColor.labelColor.setStroke(); path.stroke(); image.unlockFocus(); image.isTemplate = true; return image
    }
}
