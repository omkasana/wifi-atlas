import SwiftUI
import AppKit

struct ConnectionInfoView: View {
    @EnvironmentObject var store: AppStore
    @ViewState private var publicAddress: String?
    @ViewState private var publicDate: Date?
    @ViewState private var publicError: String?
    @ViewState private var checkingPublic = false
    @ViewState private var lookupTask: Task<Void,Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("Wi-Fi information").font(.headline); if let date = store.connectionInfo.date { Text("Updated \(date.formatted(date: .omitted,time: .standard))").font(.caption).foregroundStyle(.secondary) } }; Spacer(); if store.infoRefreshing { ProgressView().controlSize(.small) }; Button("Refresh") { store.refreshConnectionInfo() }.disabled(store.infoRefreshing); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.connectionInfo.copyText,forType: .string) } label: { Label("Copy details",systemImage: "doc.on.doc") }.disabled(store.connectionInfo.sections.isEmpty) }
            ForEach(store.connectionInfo.sections) { section in
                VStack(alignment: .leading, spacing: 10) { Text(section.title).font(.subheadline.weight(.semibold)); Grid(alignment: .topLeading,horizontalSpacing: 24,verticalSpacing: 9) { ForEach(section.rows) { row in GridRow { Text(row.label).foregroundStyle(.secondary).frame(width: 195,alignment: .leading); Text(row.value).textSelection(.enabled).frame(maxWidth: .infinity,alignment: .leading).contextMenu { Button("Copy \(row.label.lowercased())") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.value,forType: .string) }.disabled(row.value == "Unavailable") } } } }.font(.caption) }
                Divider()
            }
            VStack(alignment: .leading,spacing: 8) { HStack { Text("Internet exit IP").font(.subheadline.weight(.semibold)); Spacer(); Button(checkingPublic ? "Checking…" : "Check public IP") { checkPublicIP() }.disabled(checkingPublic) }; if let publicAddress { Text(publicAddress).textSelection(.enabled); if let publicDate { Text("Checked \(publicDate.formatted(date: .omitted,time: .standard))").font(.caption).foregroundStyle(.secondary) } }; if let publicError { Text(publicError).font(.caption).foregroundStyle(.secondary) }; Text("Optional lookup contacts Cloudflare. This is the internet exit address for your current route, which may use a VPN or Ethernet rather than Wi-Fi.").font(.caption).foregroundStyle(.secondary) }
            Text("Network names and access-point details may need Location Services permission. Unavailable fields are not exposed by macOS or are not configured. DNS values describe local configuration; VPNs and scoped resolvers can change which servers a request uses. The reported hardware MAC can differ from a private Wi-Fi address.").font(.caption).foregroundStyle(.secondary)
            Button("Allow network names") { store.wifi.requestPermission() }
        }.onAppear { store.refreshConnectionInfo() }
        .onChange(of: store.current.networkIdentity) { _,_ in resetLookup() }
        .onChange(of: store.route) { _,_ in resetLookup() }
        .onDisappear { resetLookup() }
    }
    private func resetLookup() { lookupTask?.cancel(); lookupTask = nil; checkingPublic = false; publicAddress = nil; publicDate = nil; publicError = nil }
    private func checkPublicIP() {
        checkingPublic = true; publicError = nil
        let network = store.current.networkIdentity, route = store.route
        lookupTask = Task { @MainActor in
            defer { if !Task.isCancelled { checkingPublic = false; lookupTask = nil } }
            do {
                var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!); request.timeoutInterval = 8; request.cachePolicy = .reloadIgnoringLocalCacheData
                let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil; configuration.timeoutIntervalForResource = 8
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data,response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard network == store.current.networkIdentity, route == store.route else { return }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 65536, let text = String(data: data,encoding: .utf8), let address = ConnectionInfoService.publicIP(from: text) else { throw URLError(.cannotParseResponse) }
                publicAddress = address; publicDate = Date()
            } catch { if !Task.isCancelled { publicError = "Could not look up the public IP. \(error.localizedDescription)" } }
        }
    }
}
