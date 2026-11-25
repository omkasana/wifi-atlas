import AppKit
let directory = CommandLine.arguments[1]
for base in [16, 32, 128, 256, 512] {
  for factor in [1, 2] {
    let size = base * factor
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSColor(red: 0.025, green: 0.10, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.04, y: s*0.04, width: s*0.92, height: s*0.92), xRadius: s*0.21, yRadius: s*0.21).fill()
    NSColor(red: 0.15, green: 0.85, blue: 0.92, alpha: 1).setStroke()
    for r in [0.22, 0.36, 0.50] {
        let path = NSBezierPath(); path.lineWidth = s*0.058; path.lineCapStyle = .round
        path.appendArc(withCenter: NSPoint(x: s*0.5, y: s*0.24), radius: s*r, startAngle: 49, endAngle: 131)
        path.stroke()
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: s*0.46, y: s*0.20, width: s*0.08, height: s*0.08)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let name = "icon_\(base)x\(base)\(factor == 2 ? "@2x" : "").png"
    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
  }
}
// ICNS supports PNG chunks directly, avoiding iconutil's toolchain-specific importer.
func bigEndian(_ value: Int) -> Data {
    var word = UInt32(value).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
var chunks = Data()
for (kind, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let payload = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(name))
    chunks.append(Data(kind.utf8)); chunks.append(bigEndian(payload.count + 8)); chunks.append(payload)
}
var icon = Data("icns".utf8); icon.append(bigEndian(chunks.count + 8)); icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
