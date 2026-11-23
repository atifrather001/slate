// Draws the Slate app icon (the "Stone S") and writes Resources/AppIcon.icns.
// Run from the package folder: swift Scripts/make-icon.swift
import AppKit

func c(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func fill(_ p: NSBezierPath, _ col: NSColor) { col.setFill(); p.fill() }
func grad(_ p: NSBezierPath, _ a: Int, _ b: Int, _ angle: CGFloat = -90) { NSGradient(starting: c(a), ending: c(b))!.draw(in: p, angle: angle) }
func shadow(_ blur: CGFloat, _ y: CGFloat, _ a: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: y); s.shadowColor = NSColor.black.withAlphaComponent(a); s.set()
    body(); NSGraphicsContext.restoreGraphicsState()
}
func stroke(_ pts: [CGPoint], _ w: CGFloat, _ col: NSColor) {
    let p = NSBezierPath(); p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }; col.setStroke(); p.stroke()
}
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
// Chalk texture: deterministic speckle so every size renders the same.
func speckle(_ r: NSRect, _ count: Int, _ col: NSColor, seed: UInt64) {
    var s = seed
    func rnd() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 33) / CGFloat(1 << 31) }
    col.setFill()
    for _ in 0..<count { NSBezierPath(ovalIn: NSRect(x: r.minX + rnd() * r.width, y: r.minY + rnd() * r.height, width: 2 + rnd() * 3, height: 2 + rnd() * 3)).fill() }
}

// B: modern slate stone. Bevelled tile with an S drawn as a code caret.
func conceptB() {
    shadow(24, -12, 0.35) { grad(rr(tile, 185), 0x5B6878, 0x2B333D) }
    grad(rr(tile.insetBy(dx: 10, dy: 10), 176), 0x4E5A69, 0x252C35)
    let hl = NSBezierPath(); hl.append(rr(tile.insetBy(dx: 10, dy: 10), 176)); hl.lineWidth = 6; c(0xFFFFFF, 0.08).setStroke(); hl.stroke()
    speckle(tile.insetBy(dx: 60, dy: 60), 300, c(0xFFFFFF, 0.04), seed: 3)
    for i in 0..<3 {   // faint slate layers
        let y = 280 + CGFloat(i) * 8
        fill(rr(NSRect(x: 160, y: y - CGFloat(i) * 60, width: 704, height: 4), 2), c(0x000000, 0.10))
    }
    let s = NSBezierPath(); s.lineWidth = 92; s.lineCapStyle = .round; s.lineJoinStyle = .round
    s.move(to: CGPoint(x: 668, y: 700)); s.line(to: CGPoint(x: 356, y: 700)); s.line(to: CGPoint(x: 356, y: 520))
    s.line(to: CGPoint(x: 668, y: 520)); s.line(to: CGPoint(x: 668, y: 340)); s.line(to: CGPoint(x: 356, y: 340))
    shadow(10, -6, 0.4) { NSGradient(starting: c(0x8FE3FF), ending: c(0x3C8DFF))!.draw(in: { () -> NSBezierPath in
        let g = NSBezierPath(); g.append(NSBezierPath(cgPath: s.cgPath.copy(strokingWithWidth: 92, lineCap: .round, lineJoin: .round, miterLimit: 10))); return g }(), angle: -90) }
    fill(rr(NSRect(x: 600, y: 210, width: 136, height: 30), 15), c(0xE8EEF5, 0.85))
}

func render(_ px: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!; NSGraphicsContext.current = g
    g.imageInterpolation = .high
    g.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(); NSGraphicsContext.restoreGraphicsState(); return rep
}
func save(_ rep: NSBitmapImageRep, _ path: String) { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }


let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset").path
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    save(render(size, conceptB), "\(iconset)/icon_\(size)x\(size).png")
    save(render(size * 2, conceptB), "\(iconset)/icon_\(size)x\(size)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
