// Значок Помітки: аркуш із рядками тексту, один рядок під жовтим маркером, до нього — червона стрілка.
// Запуск: swift Tools/icon.swift Resources  →  Resources/AppIcon.icns (через iconutil)
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let side = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// y вниз, як у редакторі
ctx.translateBy(x: 0, y: CGFloat(side))
ctx.scaleBy(x: 1, y: -1)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

// Основа значка за сіткою macOS: квадрат 824 з відступом 100 і заокругленням ~185.
let base = CGRect(x: 100, y: 100, width: 824, height: 824)
let basePath = NSBezierPath(roundedRect: base, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: srgb(0, 0, 0, 0.35).cgColor)
srgb(0.15, 0.27, 0.62).setFill()
basePath.fill()
ctx.restoreGState()
NSGradient(starting: srgb(0.27, 0.52, 0.98), ending: srgb(0.13, 0.24, 0.58))!.draw(in: basePath, angle: 90)

// Аркуш
let sheet = CGRect(x: 230, y: 250, width: 564, height: 470)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: srgb(0, 0, 0, 0.30).cgColor)
srgb(1, 1, 1).setFill()
NSBezierPath(roundedRect: sheet, xRadius: 36, yRadius: 36).fill()
ctx.restoreGState()

// Рядки тексту; другий — під маркером
let lines: [(CGFloat, CGFloat)] = [(330, 380), (440, 300), (550, 420), (640, 260)]
for (i, (y, w)) in lines.enumerated() {
    if i == 1 {
        srgb(1.0, 0.84, 0.0, 0.85).setFill()
        NSBezierPath(roundedRect: CGRect(x: 280, y: y - 34, width: w + 80, height: 68), xRadius: 34, yRadius: 34).fill()
    }
    srgb(0.30, 0.33, 0.40).setFill()
    NSBezierPath(roundedRect: CGRect(x: 300, y: y - 13, width: w, height: 26), xRadius: 13, yRadius: 13).fill()
}

// Стрілка знизу праворуч до виділеного рядка: тіло з тонким хвостом, наконечник, темний контур
func at(_ p: CGPoint, _ d: CGPoint, _ along: CGFloat, _ side: CGFloat) -> CGPoint {
    CGPoint(x: p.x + d.x * along - d.y * side, y: p.y + d.y * along + d.x * side)
}
let a = CGPoint(x: 820, y: 830), b = CGPoint(x: 640, y: 470)
let len = hypot(b.x - a.x, b.y - a.y)
let d = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
let w: CGFloat = 46, head: CGFloat = 170, half: CGFloat = 92
let arrow = CGMutablePath()
arrow.move(to: at(a, d, 0, w * 0.3))
arrow.addLine(to: at(b, d, -head * 0.75, w / 2))
arrow.addLine(to: at(b, d, -head, half))
arrow.addLine(to: b)
arrow.addLine(to: at(b, d, -head, -half))
arrow.addLine(to: at(b, d, -head * 0.75, -w / 2))
arrow.addLine(to: at(a, d, 0, -w * 0.3))
arrow.closeSubpath()
ctx.setLineJoin(.round)
ctx.addPath(arrow)
ctx.setStrokeColor(srgb(0.08, 0.08, 0.10, 0.9).cgColor)
ctx.setLineWidth(14)
ctx.strokePath()
ctx.addPath(arrow)
ctx.setFillColor(srgb(0.91, 0.16, 0.16).cgColor)
ctx.fillPath()
NSGraphicsContext.restoreGraphicsState()

// Набір розмірів → .icns
let set = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let master = rep.representation(using: .png, properties: [:])!
try! master.write(to: outDir.appendingPathComponent("AppIcon-1024.png"))
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current!.imageInterpolation = .high
        NSImage(data: master)!.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        try! small.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
print(p.terminationStatus == 0 ? "Значок: \(outDir.path)/AppIcon.icns" : "iconutil впав")
