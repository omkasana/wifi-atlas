import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import AtlasCore

struct SurveyView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("speedConsent") var consent = false
    @ViewState private var stage = "Layout"
    @ViewState private var tool = "Select"
    @ViewState private var layer = HeatLayer.signal
    @ViewState private var zoom = 1.0
    @ViewState private var naming: String?
    @ViewState private var name = ""
    @ViewState private var profile = "Thorough"
    @ViewState private var confirming = false
    @ViewState private var editingRoom: Room?
    @ViewState private var editingRouter: RouterMarker?
    @ViewState private var editingSpot: PlannedSpot?
    @ViewState private var editingPoint: SurveyPoint?
    @ViewState private var undo: [LayoutSnapshot] = []
    @ViewState private var redo: [LayoutSnapshot] = []
    @ViewState private var dragStart: CGPoint?
    @ViewState private var dragEnd: CGPoint?
    @ViewState private var comparison: UUID?
    @ViewState private var deleteKind: String?
    var locked: Bool { store.surveying || store.testing || store.surveyActive }
    var floor: Floor? { stage == "Layout" ? store.floor : store.displayFloor }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("A better connection, room by room.").font(.title.weight(.semibold)); Spacer(); Menu { Button("New home / office…") { naming = "Space"; name = "" }; Button("New floor…") { naming = "Floor"; name = "" }.disabled(store.selectedSpace == nil); Button("Duplicate layout") { store.duplicateSpace(); stage = "Layout" }.disabled(store.selectedSpace == nil); Button("Rename layout…") { naming = "Rename"; name = store.archive.spaces.first { $0.id == store.selectedSpace }?.name ?? "" }.disabled(store.selectedSpace == nil); Button("Delete layout…", role: .destructive) { deleteKind = "layout" }.disabled(store.selectedSpace == nil); Button("Delete floor…", role: .destructive) { deleteKind = "floor" }.disabled(store.selectedFloor == nil) } label: { Label("Layouts", systemImage: "folder.badge.plus") }.disabled(locked) }
            if store.archive.spaces.isEmpty { ContentUnavailableView { Label("Start with your space", systemImage: "house") } description: { Text("Create a home or office layout, draw rooms, and place your router. We’ll suggest where to test your laptop.") } actions: { Button("Create layout") { naming = "Space"; name = "My home" }.buttonStyle(.borderedProminent) } }
            else {
                selectors.disabled(locked)
                HStack { Picker("Step", selection: $stage) { Text("1. Build layout").tag("Layout"); Text("2. Guided survey").tag("Survey"); Text("3. Heatmap & results").tag("Results") }.pickerStyle(.segmented).disabled(store.surveying); Spacer(); Button { zoom = max(0.6, zoom - 0.2) } label: { Image(systemName: "minus.magnifyingglass") }; Text("\(Int(zoom*100))%").font(.caption).monospacedDigit(); Button { zoom = min(3, zoom + 0.2) } label: { Image(systemName: "plus.magnifyingglass") } }
                if let floor {
                    if stage == "Layout" { layoutTools }
                    else if stage == "Survey" { surveyControls }
                    else { resultTools }
                    ScrollView([.horizontal, .vertical]) {
                        map(floor).frame(width: 720*zoom, height: 720*zoom/floor.aspect)
                    }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)).frame(minHeight: 210)
                    if stage == "Layout" { layoutList(floor).frame(maxHeight: 155) }
                    else { results.frame(maxHeight: 170) }
                } else { ContentUnavailableView("Add a floor to this layout", systemImage: "square.stack", description: Text("Use the Layouts menu to add a floor.")) }
            }
        }.padding(24)
        .onChange(of: store.selectedFloor) { _, _ in undo = []; redo = []; comparison = nil; stage = "Layout" }
        .sheet(isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) { VStack(alignment: .leading, spacing: 18) { Text(naming == "Rename" ? "Rename layout" : "New \(naming?.lowercased() ?? "layout")").font(.title2); TextField("Name", text: $name); HStack { Button("Cancel") { naming = nil }; Spacer(); Button("Save") { if naming == "Space" { store.newSpace(name) } else if naming == "Floor" { store.newFloor(name) } else if let i = store.archive.spaces.firstIndex(where: { $0.id == store.selectedSpace }) { store.archive.spaces[i].name = name; store.save() }; naming = nil; stage = "Layout" }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction) } }.padding(24).frame(width: 360) }
        .sheet(item: $editingRoom) { room in RoomEditor(room: room) { replacement in changeLayout { f in if let i = f.rooms.firstIndex(where: { $0.id == room.id }) { f.rooms[i] = replacement } }; editingRoom = nil } }
        .sheet(item: $editingRouter) { router in MarkerEditor(name: router.name, position: router.position, title: "Router / mesh point") { n, p in changeLayout { f in if let i = f.routers?.firstIndex(where: { $0.id == router.id }) { f.routers?[i].name = n; f.routers?[i].position = p } }; editingRouter = nil } }
        .sheet(item: $editingSpot) { spot in MarkerEditor(name: spot.name, position: spot.position, title: "Suggested test spot") { n, p in store.editSession { s in if let i = s.plannedSpots?.firstIndex(where: { $0.id == spot.id }) { s.plannedSpots?[i].name = n; s.plannedSpots?[i].position = p } }; editingSpot = nil } }
        .sheet(item: $editingPoint) { point in PointEditor(point: point) { replacement in store.editSession { s in if let i = s.points.firstIndex(where: { $0.id == point.id }) { s.points[i] = replacement } }; editingPoint = nil } onDelete: { store.editSession { s in s.points.removeAll { $0.id == point.id }; if let i = s.plannedSpots?.firstIndex(where: { $0.completedPointID == point.id }) { s.plannedSpots?[i].completedPointID = nil } }; editingPoint = nil } }
        .sheet(isPresented: $confirming) { surveySetup }
        .confirmationDialog("Delete this \(deleteKind ?? "layout") and its saved surveys?", isPresented: Binding(get: { deleteKind != nil }, set: { if !$0 { deleteKind = nil } })) { Button("Delete", role: .destructive) { if deleteKind == "layout" { store.archive.spaces.removeAll { $0.id == store.selectedSpace }; store.selectSpace(store.archive.spaces.first?.id) } else if let s = store.archive.spaces.firstIndex(where: { $0.id == store.selectedSpace }) { store.archive.spaces[s].floors.removeAll { $0.id == store.selectedFloor }; store.selectFloor(store.archive.spaces[s].floors.first?.id) }; store.save(); deleteKind = nil } }
    }
    var selectors: some View { HStack {
        Picker("Layout", selection: Binding(get: { store.selectedSpace }, set: { store.selectSpace($0) })) { ForEach(store.archive.spaces) { Text($0.name).tag(Optional($0.id)) } }
        Picker("Floor", selection: Binding(get: { store.selectedFloor }, set: { store.selectFloor($0) })) { ForEach(store.archive.spaces.first(where: { $0.id == store.selectedSpace })?.floors ?? []) { Text($0.name).tag(Optional($0.id)) } }
        if stage != "Layout" { Picker("Survey", selection: $store.selectedSession) { ForEach(store.floor?.sessions ?? []) { Text($0.name).tag(Optional($0.id)) } } }
    } }
    var layoutTools: some View { VStack(alignment: .leading, spacing: 8) { HStack { Picker("Tool", selection: $tool) { ForEach(["Select", "Draw room", "Move room", "Resize room", "Place router", "Place door"], id: \.self) { Text($0) } }.frame(width: 220); Button("Import plan…") { importPlan() }; Button { undoLayout() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undo.isEmpty).help("Undo layout edit"); Button { redoLayout() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redo.isEmpty).help("Redo layout edit"); Spacer(); Button("Plan survey") { confirming = true }.buttonStyle(.borderedProminent).disabled(store.floor?.rooms.isEmpty != false || (store.floor?.routers ?? []).isEmpty) }.disabled(locked); Text("Draw rooms on the grid, then place your router. Drag with Move/Resize to adjust rooms; click a room or marker to edit it. Imported images need room outlines.").font(.caption).foregroundStyle(.secondary) } }
    var surveySetup: some View {
        let spots = store.floor.map(SurveyPlanner.spots) ?? []
        let thorough = profile == "Thorough"
        return VStack(alignment: .leading, spacing: 18) { Text("Plan your Wi-Fi survey").font(.title2); Text("We suggest each room’s center and four corners. You can adjust, add, or skip spots before measuring."); Picker("Test profile", selection: $profile) { Text("Thorough · 30 sec / 250 MB per spot").tag("Thorough"); Text("Quick · 20 sec / 50 MB per spot").tag("Quick") }; Text("\(spots.count) suggested spots · up to \(Int(ceil(Double(spots.count * (thorough ? 33 : 23))/60))) minutes of testing, plus walking · up to \(Double(spots.count * (thorough ? 250 : 50))/1000, specifier: "%.2f") GB payload data.").font(.headline); Text("Cloudflare receives your IP address and test traffic. Signal is monitored throughout; speed is tested only when you confirm you are at a spot. Router markers do not predict speeds.").font(.caption).foregroundStyle(.secondary); HStack { Button("Cancel") { confirming = false }; Spacer(); Button("Create guided survey") { consent = true; store.beginSurvey(profile: profile); stage = "Survey"; confirming = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) } }.padding(24).frame(width: 500)
    }
    var surveyControls: some View { VStack(alignment: .leading, spacing: 10) {
        if let spot = store.currentSpot {
            HStack { VStack(alignment: .leading, spacing: 4) { Text(store.surveying ? "Stay still while we measure" : "Move your laptop to \(spot.name)").font(.headline); Text(store.surveying ? (store.testing ? store.status : "Letting the signal settle…") : "The highlighted numbered circle is your next spot. The Mac cannot detect your indoor position.").font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.surveyActive { Button("Pause") { store.pauseSurvey() }; Button("I’m here—start measuring") { store.capture(at: spot.position, name: spot.name) }.buttonStyle(.borderedProminent).disabled(store.surveying || store.testing || !store.current.connected) } else { Button("Resume survey") { store.resumeSurvey() }.buttonStyle(.borderedProminent) }; Button("Skip spot") { store.skipSpot() }.disabled(store.surveying) }
            if store.testing { ProgressView(value: store.progress); Text("↓ \(number(store.testDownload, digits: 1))  ↑ \(number(store.testUpload, digits: 1)) Mbps · \(Strength.label(store.current.rssi)) signal").font(.caption).monospacedDigit() }
            HStack { Text("\(store.session?.points.count ?? 0) measured / \(store.session?.plannedSpots?.count ?? 0) planned").font(.caption); Spacer(); Toggle("Add test spots by clicking map", isOn: Binding(get: { tool == "Add spot" }, set: { tool = $0 ? "Add spot" : "Select" })).toggleStyle(.checkbox).disabled(store.surveying) }
        } else { HStack { Text(store.surveyFinished ? "Survey complete. Compare rooms and explore your heatmap." : "Create a guided survey from your layout first.").font(.headline); Spacer(); Button("View heatmap") { stage = "Results" }; Button("New survey") { confirming = true }.disabled(locked) } }
    } }
    var resultTools: some View { HStack { Picker("Show", selection: $layer) { ForEach(HeatLayer.allCases) { Text($0 == .latency ? "Response time" : $0.rawValue).tag($0) } }.frame(width: 190); Picker("Compare", selection: $comparison) { Text("No comparison").tag(Optional<UUID>.none); ForEach(store.floor?.sessions.filter { $0.id != store.selectedSession } ?? []) { Text($0.name).tag(Optional($0.id)) } }.frame(width: 230); Spacer(); Menu("Export") { Button("CSV measurements…") { exportCSV() }; Button("PNG heatmap…") { exportImage(pdf: false) }; Button("PDF survey report…") { exportImage(pdf: true) } }; Button("New survey") { confirming = true }.disabled(locked) } }
    func map(_ floor: Floor) -> some View {
        let session = stage == "Layout" ? SurveySession(name: "Layout") : store.session ?? SurveySession(name: "Survey")
        return HeatmapView(floor: floor, session: session, layer: layer, editing: stage == "Layout")
            .overlay { if stage == "Survey" { GeometryReader { geometry in ForEach(Array((store.session?.plannedSpots ?? []).enumerated()), id: \.element.id) { index, spot in Button { if !store.surveying { editingSpot = spot } } label: { Text("\(index+1)").font(.caption.bold()).foregroundStyle(.white).frame(width: spot.id == store.currentSpot?.id ? 32 : 23, height: spot.id == store.currentSpot?.id ? 32 : 23).background(spot.skipped ? .gray : spot.completedPointID != nil ? .green : spot.id == store.currentSpot?.id ? .blue : .orange, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2)) }.buttonStyle(.plain).help(spot.name).accessibilityLabel("Test spot \(index+1), \(spot.name)").position(x: spot.position.x * geometry.size.width, y: spot.position.y * geometry.size.height) } } } }
            .overlay { if let a = dragStart, let b = dragEnd { Rectangle().fill(.blue.opacity(0.12)).border(.blue).frame(width: abs(a.x-b.x), height: abs(a.y-b.y)).position(x: (a.x+b.x)/2, y: (a.y+b.y)/2) } }
            .onTapGesture(coordinateSpace: .local) { location in tapped(normalize(location, floor), floor) }
            .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { value in guard stage == "Layout", !locked else { return }; dragStart = value.startLocation; dragEnd = value.location }.onEnded { value in defer { dragStart = nil; dragEnd = nil }; guard stage == "Layout", !locked else { return }; drag(from: normalize(value.startLocation, floor), to: normalize(value.location, floor), floor: floor) })
    }
    func normalize(_ p: CGPoint, _ f: Floor) -> MapPoint { MapPoint(x: p.x/(720*zoom), y: p.y/(720*zoom/f.aspect)) }
    func snap(_ x: Double) -> Double { (x*40).rounded()/40 }
    func tapped(_ p: MapPoint, _ floor: Floor) {
        guard !store.surveying else { return }
        if stage == "Survey", tool == "Add spot" { guard floor.rooms.contains(where: { $0.contains(p) }) else { return }; store.editSession { s in let count = s.plannedSpots?.count ?? 0; s.plannedSpots?.append(PlannedSpot(name: "Extra spot \(count+1)", position: p)) }; return }
        if stage == "Results" { if let point = store.session?.points.first(where: { hypot($0.position.x-p.x, $0.position.y-p.y) < 0.03 }) { editingPoint = point }; return }
        guard stage == "Layout", !locked else { return }
        if tool == "Place router" { changeLayout { f in if f.routers == nil { f.routers = [] }; let count = f.routers?.count ?? 0; f.routers?.append(RouterMarker(name: "Router \(count+1)", position: MapPoint(x: snap(p.x), y: snap(p.y)))) } }
        else if tool == "Place door" { changeLayout { f in if f.doors == nil { f.doors = [] }; f.doors?.append(DoorMarker(position: MapPoint(x: snap(p.x), y: snap(p.y)))) } }
        else if tool == "Select" { if let r = floor.routers?.first(where: { hypot($0.position.x-p.x, $0.position.y-p.y) < 0.04 }) { editingRouter = r } else { editingRoom = floor.rooms.last { $0.contains(p) } } }
    }
    func drag(from a: MapPoint, to b: MapPoint, floor: Floor) {
        if tool == "Draw room" { let x = snap(min(a.x,b.x)), y = snap(min(a.y,b.y)), w = snap(abs(a.x-b.x)), h = snap(abs(a.y-b.y)); guard w >= 0.05, h >= 0.05 else { return }; changeLayout { $0.rooms.append(Room(name: "Room \($0.rooms.count+1)", origin: MapPoint(x: x,y: y), width: min(w,1-x), height: min(h,1-y))) } }
        else if let room = floor.rooms.last(where: { $0.contains(a) }), tool == "Move room" || tool == "Resize room" { changeLayout { f in guard let i = f.rooms.firstIndex(where: { $0.id == room.id }) else { return }; if tool == "Move room" { f.rooms[i].origin = MapPoint(x: min(1-room.width,max(0,snap(room.origin.x+b.x-a.x))), y: min(1-room.height,max(0,snap(room.origin.y+b.y-a.y)))) } else { f.rooms[i].width = min(1-room.origin.x,max(0.05,snap(b.x-room.origin.x))); f.rooms[i].height = min(1-room.origin.y,max(0.05,snap(b.y-room.origin.y))) } } }
    }
    func changeLayout(_ action: (inout Floor) -> Void) { guard let f = store.floor else { return }; undo.append(LayoutSnapshot(f)); if undo.count > 20 { undo.removeFirst() }; redo = []; store.editFloor(action) }
    func apply(_ snapshot: LayoutSnapshot) { store.editFloor { $0.rooms = snapshot.rooms; $0.routers = snapshot.routers; $0.doors = snapshot.doors; $0.imageData = snapshot.imageData; $0.aspect = snapshot.aspect } }
    func undoLayout() { guard let last = undo.popLast(), let f = store.floor else { return }; redo.append(LayoutSnapshot(f)); apply(last) }
    func redoLayout() { guard let last = redo.popLast(), let f = store.floor else { return }; undo.append(LayoutSnapshot(f)); apply(last) }
    func layoutList(_ f: Floor) -> some View { ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(f.rooms) { room in HStack { Button(room.name) { editingRoom = room }.buttonStyle(.link); Spacer(); Button("Remove room", role: .destructive) { changeLayout { $0.rooms.removeAll { $0.id == room.id } } } }.font(.caption) }; ForEach(f.routers ?? []) { router in HStack { Label(router.name, systemImage: "wifi.router"); Button("Edit") { editingRouter = router }; Spacer(); Button("Remove", role: .destructive) { changeLayout { $0.routers?.removeAll { $0.id == router.id } } } }.font(.caption) }; ForEach(Array((f.doors ?? []).enumerated()), id: \.element.id) { i, door in HStack { Text("Door \(i+1)"); Spacer(); Button("Remove", role: .destructive) { changeLayout { $0.doors?.removeAll { $0.id == door.id } } } }.font(.caption) } }.disabled(locked) } }
    var results: some View { ScrollView { VStack(alignment: .leading, spacing: 8) {
        if stage == "Survey" { ForEach(store.session?.plannedSpots ?? []) { spot in HStack { Text(spot.name); Spacer(); Text(spot.completedPointID != nil ? "Measured" : spot.skipped ? "Skipped" : "Not measured").foregroundStyle(.secondary); Button("Edit") { editingSpot = spot }.disabled(store.surveying || spot.completedPointID != nil); if spot.completedPointID == nil { Button(spot.skipped ? "Restore" : "Skip") { store.editSession { s in if let i = s.plannedSpots?.firstIndex(where: { $0.id == spot.id }) { s.plannedSpots?[i].skipped.toggle() } } }.disabled(store.surveying) }; Button("Remove", role: .destructive) { store.editSession { $0.plannedSpots?.removeAll { $0.id == spot.id } } }.disabled(store.surveying || spot.completedPointID != nil) }.font(.caption) } }
        else { Text("Measured spots · best to worst for this metric").font(.headline); ForEach(ranked) { p in HStack { Button(p.name) { editingPoint = p }.buttonStyle(.link); Spacer(); Text(presentation(p)); if let old = comparisonPoint(p), let before = old.value(layer), let after = p.value(layer) { Text(layer == .signal ? "Previously \(Strength.label(before))" : String(format: "Change %+.1f %@", after-before, layer.unit)).foregroundStyle(.secondary) } }.font(.caption) }; roomRanks; Text("Colored shading is an estimate. Blank space needs more measurements. Router markers do not predict coverage.").font(.caption).foregroundStyle(.secondary) }
    } } }
    var ranked: [SurveyPoint] { (store.session?.points ?? []).sorted { let a = $0.value(layer), b = $1.value(layer); guard let a else { return false }; guard let b else { return true }; return layer == .latency ? a < b : a > b } }
    func presentation(_ p: SurveyPoint) -> String { layer == .signal ? "\(Strength.label(p.meanSignal)) · \(number(Strength.score(p.meanSignal))) / 100" : "\(number(p.value(layer), digits: 1)) \(layer.unit)" }
    func comparisonPoint(_ p: SurveyPoint) -> SurveyPoint? { guard let q = store.floor?.sessions.first(where: { $0.id == comparison })?.points.min(by: { hypot($0.position.x-p.position.x,$0.position.y-p.position.y) < hypot($1.position.x-p.position.x,$1.position.y-p.position.y) }), hypot(q.position.x-p.position.x,q.position.y-p.position.y) < 0.035 else { return nil }; return q }
    var roomRanks: some View { VStack(alignment: .leading, spacing: 6) { Divider(); Text("Room averages").font(.headline); ForEach((floor?.rooms ?? []).sorted { roomAverage($0) > roomAverage($1) }) { room in let values = (store.session?.points ?? []).filter { room.contains($0.position) }.compactMap { $0.value(layer) }; HStack { Text(room.name); Spacer(); if let mean = Statistics.mean(values) { Text(layer == .signal ? Strength.label(mean) : "\(number(mean, digits: 1)) \(layer.unit)") } else { Text("Not measured") } }.font(.caption) } } }
    func roomAverage(_ room: Room) -> Double { let mean = Statistics.mean((store.session?.points ?? []).filter { room.contains($0.position) }.compactMap { $0.value(layer) }); return mean.map { layer == .latency ? -$0 : $0 } ?? -.infinity }
    func importPlan() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let image = url.pathExtension.lowercased() == "pdf" ? PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: NSSize(width: 1800,height: 1800), for: .mediaBox) : NSImage(data: data)
            guard let image, image.size.width > 0, image.size.height > 0, (0.25...4).contains(image.size.width/image.size.height) else { throw CocoaError(.fileReadCorruptFile) }
            let scale = min(1,1800/max(image.size.width,image.size.height)), size = NSSize(width: image.size.width*min(1,1800/max(image.size.width,image.size.height)),height: image.size.height*min(1,1800/max(image.size.width,image.size.height)))
            _ = scale
            let resized = NSImage(size: size); resized.lockFocus(); image.draw(in: NSRect(origin: .zero,size: size)); resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png,properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
            changeLayout { $0.imageData = png; $0.aspect = size.width/size.height; $0.rooms = []; $0.routers = []; $0.doors = [] }
        } catch { store.error = "Could not import plan. Use a readable PNG/JPEG/PDF with a width-to-height ratio between 1:4 and 4:1. \(error.localizedDescription)" }
    }
    func exportCSV() { guard let session = store.session else { return }; save(Data(Statistics.csv(session).utf8), name: "Atlas-measurements.csv", type: .commaSeparatedText) }
    func exportImage(pdf: Bool) {
        guard let floor = store.displayFloor, let session = store.session else { return }
        let report = VStack(alignment: .leading, spacing: 14) { Text("WiFi Atlas · \(floor.name)").font(.title); Text("\(session.name) · \(session.date.formatted())").font(.headline); HeatmapView(floor: floor, session: session, layer: layer).frame(width: 1000,height: 1000/floor.aspect); Text("\(layer == .signal ? "Wi-Fi strength, estimated score / 100" : layer == .latency ? "Response time (ms)" : "\(layer.rawValue) (Mbps)") · shading is estimated · blank areas need measurements").font(.caption); ForEach(ranked) { p in HStack { Text(p.name); Spacer(); Text(presentation(p)) }.font(.caption) }; Text("Exported \(Date().formatted()). Router markers are annotations; results reflect this survey only.").font(.caption) }.padding(28).frame(width: 1056).background(.white).foregroundStyle(.black).environment(\.colorScheme,.light)
        if pdf { let renderer = ImageRenderer(content: report); let data = NSMutableData(); renderer.render { size, render in guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return }; var bounds = CGRect(origin: .zero,size: size); guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { return }; context.beginPDFPage(nil); render(context); context.endPDFPage(); context.closePDF() }; save(data as Data,name: "Atlas-survey.pdf",type: .pdf) }
        else { guard let image = ImageRenderer(content: report).nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png,properties: [:]) else { store.error = "Could not render report."; return }; save(png,name: "Atlas-heatmap.png",type: .png) }
    }
    func save(_ data: Data, name: String, type: UTType) { let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]; if panel.runModal() == .OK, let url = panel.url { do { try data.write(to: url,options: .atomic) } catch { store.error = error.localizedDescription } } }
}
struct HeatmapView: View {
    let floor: Floor
    let session: SurveySession
    let layer: HeatLayer
    var editing = false
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero,size: size)),with: .color(Color(nsColor: .controlBackgroundColor)))
            if let data = floor.imageData, let image = NSImage(data: data) { context.draw(Image(nsImage: image),in: CGRect(origin: .zero,size: size)) }
            if editing { var grid = Path(); for x in stride(from: 0.0,through: 1,by: 0.025) { grid.move(to: CGPoint(x: x*size.width,y: 0)); grid.addLine(to: CGPoint(x: x*size.width,y: size.height)) }; for y in stride(from: 0.0,through: 1,by: 0.025) { grid.move(to: CGPoint(x: 0,y: y*size.height)); grid.addLine(to: CGPoint(x: size.width,y: y*size.height)) }; context.stroke(grid,with: .color(.secondary.opacity(0.12)),lineWidth: 0.5) }
            else { let columns = 48, rows = max(12,Int(48/floor.aspect)); for row in 0..<rows { for col in 0..<columns { let p = MapPoint(x: (Double(col)+0.5)/Double(columns),y: (Double(row)+0.5)/Double(rows)); if let value = Statistics.estimate(at: p,points: session.points,rooms: floor.rooms,layer: layer) { let rect = CGRect(x: Double(col)*size.width/Double(columns),y: Double(row)*size.height/Double(rows),width: size.width/Double(columns)+0.5,height: size.height/Double(rows)+0.5); context.fill(Path(rect),with: .color(color(value).opacity(0.38))) } } } }
            for room in floor.rooms { let rect = CGRect(x: room.origin.x*size.width,y: room.origin.y*size.height,width: room.width*size.width,height: room.height*size.height); context.stroke(Path(rect),with: .color(.primary.opacity(0.6)),lineWidth: 2); context.draw(Text(room.name).font(.caption).foregroundColor(.primary),at: CGPoint(x: rect.midX,y: rect.minY+13)) }
            for door in floor.doors ?? [] { let rect = CGRect(x: door.position.x*size.width-9,y: door.position.y*size.height-4,width: 18,height: 8); context.fill(Path(rect),with: .color(.orange)) }
            for router in floor.routers ?? [] { let point = CGPoint(x: router.position.x*size.width,y: router.position.y*size.height); context.draw(Image(systemName: "wifi.router.fill"),at: point); context.draw(Text(router.name).font(.caption2),at: CGPoint(x: point.x,y: point.y+16)) }
            for (index,point) in session.points.enumerated() { let center = CGPoint(x: point.position.x*size.width,y: point.position.y*size.height), circle = Path(ellipseIn: CGRect(x: center.x-9,y: center.y-9,width: 18,height: 18)); context.fill(circle,with: .color(point.value(layer).map(color) ?? .gray)); context.stroke(circle,with: .color(.white),lineWidth: 2); context.draw(Text("\(index+1)").font(.system(size: 9,weight: .bold)).foregroundColor(.white),at: center) }
        }.accessibilityLabel("Layout with \(floor.rooms.count) rooms, \(floor.routers?.count ?? 0) routers and \(session.points.count) measured spots. Editing controls and measured values are available in the lists below.")
        .overlay(alignment: .bottomLeading) { if !editing { HStack(spacing: 5) { Text("Worse"); LinearGradient(colors: [.red,.yellow,.green],startPoint: .leading,endPoint: .trailing).frame(width: 80,height: 6); Text("Better · shading is estimated") }.font(.caption2).padding(7).background(.regularMaterial,in: Capsule()).padding(8) } }
    }
    func color(_ value: Double) -> Color { Color(hue: layer.quality(value)*0.33,saturation: 0.82,brightness: 0.8) }
}
struct MarkerEditor: View {
    @ViewState var name: String
    @ViewState var position: MapPoint
    let title: String
    let save: (String,MapPoint) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View { Form { Text(title).font(.title2); TextField("Name",text: $name); Slider(value: $position.x,in: 0...1) { Text("Left ↔ right") }; Slider(value: $position.y,in: 0...1) { Text("Top ↔ bottom") }; HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") { save(name,position) }.keyboardShortcut(.defaultAction).disabled(name.isEmpty) } }.padding(24).frame(width: 410) }
}
struct RoomEditor: View {
    @ViewState var room: Room
    let save: (Room) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View { Form { Text("Edit room").font(.title2); TextField("Room name",text: $room.name); Slider(value: $room.origin.x,in: 0...max(0.001,1-room.width)) { Text("Left ↔ right") }; Slider(value: $room.origin.y,in: 0...max(0.001,1-room.height)) { Text("Top ↔ bottom") }; Slider(value: $room.width,in: 0.05...max(0.05,1-room.origin.x)) { Text("Width") }; Slider(value: $room.height,in: 0.05...max(0.05,1-room.origin.y)) { Text("Height") }; HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") { save(room) }.keyboardShortcut(.defaultAction).disabled(room.name.isEmpty) } }.padding(24).frame(width: 430) }
}
struct PointEditor: View {
    @ViewState var point: SurveyPoint
    let onSave: (SurveyPoint) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View { Form { Text("Measured spot").font(.title2); TextField("Name",text: $point.name); Text("\(Strength.label(point.meanSignal)) signal · \(number(Strength.score(point.meanSignal))) / 100"); Text("\(point.readings.count) readings · \(point.date.formatted())").font(.caption).foregroundStyle(.secondary); Text("Measured positions belong to this survey’s saved layout. Retest a planned spot to correct a misplaced measurement.").font(.caption); HStack { Button("Delete measurement",role: .destructive) { onDelete() }; Spacer(); Button("Cancel") { dismiss() }; Button("Save") { onSave(point) }.keyboardShortcut(.defaultAction).disabled(point.name.isEmpty) } }.padding(24).frame(width: 460) }
}
