import SwiftUI
import WidgetKit
import AppIntents
import AtlasCore

enum AtlasSummary: String, AppEnum {
    case connection, speed, survey
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Summary")
    static var caseDisplayRepresentations: [AtlasSummary: DisplayRepresentation] = [.connection: "Connection", .speed: "Last speed test", .survey: "Survey progress"]
}
struct AtlasWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "WiFi Atlas summary"
    static var description = IntentDescription("Choose a connection, speed-test, or survey summary.")
    @Parameter(title: "Show", default: .connection) var summary: AtlasSummary
}
struct AtlasEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let summary: AtlasSummary
}
struct AtlasProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AtlasEntry { AtlasEntry(date: Date(), snapshot: nil, summary: .connection) }
    func snapshot(for configuration: AtlasWidgetConfiguration, in context: Context) async -> AtlasEntry { entry(configuration.summary) }
    func timeline(for configuration: AtlasWidgetConfiguration, in context: Context) async -> Timeline<AtlasEntry> { Timeline(entries: [entry(configuration.summary)], policy: .after(Date().addingTimeInterval(900))) }
    private func entry(_ summary: AtlasSummary) -> AtlasEntry {
        var snapshot: WidgetSnapshot?
        if let group = Bundle.main.object(forInfoDictionaryKey: "AtlasAppGroup") as? String, !group.contains("$("), let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group), let data = try? Data(contentsOf: folder.appendingPathComponent("widget.json")) { snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) }
        return AtlasEntry(date: Date(), snapshot: snapshot, summary: summary)
    }
}
struct AtlasWidgetView: View {
    let entry: AtlasEntry
    @Environment(\.widgetFamily) var family
    func format(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WiFi Atlas", systemImage: "wifi").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let s = entry.snapshot {
                switch entry.summary {
                case .connection:
                    Text(s.strengthLabel).font(.title2.weight(.semibold)); ProgressView(value: s.strength ?? 0, total: 100).tint(.green); Text(s.network).font(.caption).lineLimit(1)
                    if family == .systemMedium { Text("Estimated Wi-Fi strength · \(format(s.strength)) / 100").font(.caption).foregroundStyle(.secondary) }
                case .speed:
                    Text("↓ \(format(s.download))").font(.title2.weight(.semibold)).monospacedDigit(); Text("↑ \(format(s.upload)) Mbps").monospacedDigit(); if let date = s.testDate { Text("Tested \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) } else { Text("No completed test").font(.caption) }
                case .survey:
                    Text(s.space).font(.headline).lineLimit(1); Text("\(s.completed) / \(s.total) spots measured").font(.caption); ProgressView(value: Double(s.completed), total: Double(max(1,s.total)))
                }
                Spacer(minLength: 0)
                Text("Updated \(s.date.formatted(date: .omitted,time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                if Date().timeIntervalSince(s.date) > 300 { Text("Open app to refresh").font(.caption2).foregroundStyle(.secondary) }
            } else { Text("Open WiFi Atlas").font(.headline); Text("Your saved summary will appear here after the app runs.").font(.caption).foregroundStyle(.secondary) }
        }.containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "wifiatlas://\(entry.summary == .survey ? "survey" : entry.summary == .speed ? "speed" : "overview")"))
    }
}
@main struct AtlasWidgets: Widget {
    let kind = "AtlasSummary"
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: kind, intent: AtlasWidgetConfiguration.self, provider: AtlasProvider()) { AtlasWidgetView(entry: $0) }.configurationDisplayName("WiFi Atlas").description("Connection, last speed test, or survey progress. Updated periodically while the app runs.").supportedFamilies([.systemSmall,.systemMedium]) }
}
