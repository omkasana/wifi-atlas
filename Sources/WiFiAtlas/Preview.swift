import SwiftUI
import AppKit
import AtlasCore

/// Explicit developer-only rendering path. Fixtures never enter the live application or disk archive.
@MainActor enum AppPreview {
    static func render(to path: String) {
        _ = NSApplication.shared
        let store = AppStore(preview: true)
        store.current = Reading(ssid: "Home Wi-Fi", rssi: -52, noise: -94, linkRate: 866, channel: 36, band: "5 GHz", connected: true)
        store.traffic = RateSample(download: 32.4, upload: 6.8)
        store.route = "Wi-Fi connection"
        for i in 0..<60 {
            var reading = Reading(ssid: "Home Wi-Fi", rssi: -52 + sin(Double(i)/5)*3, noise: -94, connected: true); reading.date = Date().addingTimeInterval(Double(i-60)); store.live.append(reading)
            var rate = RateSample(download: 30 + sin(Double(i)/4)*10, upload: 6 + cos(Double(i)/5)*3); rate.date = reading.date; store.trafficHistory.append(rate)
        }
        var test = SpeedResult(); test.download = 324.5; test.upload = 86.2; test.latency = 18; test.jitter = 3; store.archive.tests = [test]
        let content = DashboardView().environmentObject(store).frame(width: 1050,height: 1250).background(.white).environment(\.colorScheme,.light)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -5000,y: -5000,width: 1050,height: 1250), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderBack(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds,to: bitmap)
        guard let png = bitmap.representation(using: .png,properties: [:]) else { return }
        window.orderOut(nil)
        do { try png.write(to: URL(fileURLWithPath: path)); print("Rendered preview: \(path)") } catch { fputs("\(error)\n",stderr) }
    }
}
