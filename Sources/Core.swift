// Помітка — ядро: позначки на знімку, малювання, копіювання в буфер, пошук нових знімків.
// Тут немає вікон, тому все це перевіряє Tests/main.swift без екрана.
import AppKit
import CoreImage
import ImageIO

// MARK: - Інструменти й кольори

/// Інструмент редактора. Номер + 1 — клавіша-скорочення (1…5).
enum Tool: Int, CaseIterable {
    case arrow, rect, marker, text, blur

    var title: String {
        switch self {
        case .arrow: "Стрілка"
        case .rect: "Рамка"
        case .marker: "Маркер"
        case .text: "Текст"
        case .blur: "Сховати"
        }
    }

    /// Значок SF Symbols на кнопці інструмента.
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .marker: "highlighter"
        case .text: "textformat"
        case .blur: "eye.slash"
        }
    }

    /// Колір за замовчуванням: маркер жовтий, як справжній; решта червоні — їх видно на будь-якому тлі.
    var defaultInk: Ink { self == .marker ? .yellow : .red }
}

/// Кольори палітри.
enum Ink: Int, CaseIterable {
    case red, yellow, blue, green

    var color: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 0.91, green: 0.16, blue: 0.16, alpha: 1)
        case .yellow: NSColor(srgbRed: 1.00, green: 0.84, blue: 0.00, alpha: 1)
        case .blue: NSColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1)
        case .green: NSColor(srgbRed: 0.13, green: 0.66, blue: 0.30, alpha: 1)
        }
    }

    var title: String {
        switch self {
        case .red: "Червоний"
        case .yellow: "Жовтий"
        case .blue: "Синій"
        case .green: "Зелений"
        }
    }
}

/// Розміри позначок у пунктах екрана; у пікселі знімка їх переводить `Canvas.scale`,
/// тож стрілка однаково товста і на знімку з Retina, і з простого монітора.
enum Style {
    static let arrow: CGFloat = 4       // товщина тіла стрілки
    static let rect: CGFloat = 3        // товщина рамки
    static let marker: CGFloat = 18     // ширина смуги маркера
    static let markerAlpha: CGFloat = 0.55
    static let text: CGFloat = 20       // розмір тексту
    static let halo: CGFloat = 1.5      // біла облямівка: позначку видно і на темному тлі
    static let block: CGFloat = 10      // розмір квадрата в «Сховати»
}

// MARK: - Позначки

/// Одна позначка. Координати — у пікселях знімка, початок у верхньому лівому куті.
enum Mark {
    case arrow(from: CGPoint, to: CGPoint, ink: Ink)
    case rect(CGRect, ink: Ink)
    case marker([CGPoint], ink: Ink)
    case text(String, at: CGPoint, ink: Ink)
    case blur(CGRect)

    /// Чи лишати позначку: клік без руху не має залишати сміття.
    func isVisible(minSize: CGFloat) -> Bool {
        switch self {
        case let .arrow(a, b, _): hypot(b.x - a.x, b.y - a.y) >= minSize
        case let .rect(r, _), let .blur(r): r.width >= minSize && r.height >= minSize
        case let .marker(points, _): points.count >= 2
        case let .text(s, _, _): !s.isEmpty
        }
    }
}

/// Прямокутник між двома кутами — у якому б напрямку не тягли мишу.
func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}

// MARK: - Полотно

/// Знімок, готовий до розмітки.
struct Canvas {
    let image: CGImage
    /// Пікселів на пункт: 2 — знімок з екрана Retina, 1 — зі звичайного монітора.
    let scale: CGFloat
    /// Той самий знімок розмитими квадратами — звідси «Сховати» бере закриті ділянки.
    let pixelated: CGImage

    var size: CGSize { CGSize(width: image.width, height: image.height) }

    init(image: CGImage, scale: CGFloat) {
        let s = min(3, max(1, scale.rounded()))
        self.image = image
        self.scale = s
        pixelated = Self.pixelate(image, block: Style.block * s) ?? image
    }

    /// Відкрити файл. Масштаб — з DPI у файлі: знімок з Retina macOS пише як 144.
    init?(contentsOf url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let dpi = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        self.init(image: img, scale: dpi / 72)
    }

    /// Картинка з буфера обміну (наприклад, знімок через ⌃⌘⇧4).
    init?(pasteboard: NSPasteboard) {
        guard let img = NSImage(pasteboard: pasteboard),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              img.size.width > 0 else { return nil }
        self.init(image: cg, scale: CGFloat(cg.width) / img.size.width)
    }

    /// Квадрати з попереднім розмиттям: кожен квадрат — середній колір ділянки,
    /// тож із закритого пароля не лишається ні літер, ні їхніх обрисів.
    static func pixelate(_ image: CGImage, block: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let blur = CIFilter(name: "CIGaussianBlur"), let pixel = CIFilter(name: "CIPixellate") else { return nil }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(block / 2, forKey: kCIInputRadiusKey)
        pixel.setValue(blur.outputImage, forKey: kCIInputImageKey)
        pixel.setValue(block, forKey: kCIInputScaleKey)
        pixel.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let out = pixel.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(out, from: input.extent)
    }

    // MARK: малювання

    /// Малює знімок і позначки. Одиниці — пікселі знімка, вісь y — вниз.
    /// Один код і для вікна, і для буфера: що бачиш, те й вставиш.
    func render(_ marks: [Mark], in ctx: CGContext) {
        draw(image, in: CGRect(origin: .zero, size: size), ctx)
        for mark in marks { draw(mark, ctx) }
    }

    /// Шрифт тексту; той самий бере поле введення у вікні (з `zoom`), щоб текст не стрибав після Enter.
    func textFont(zoom: CGFloat = 1) -> NSFont {
        .systemFont(ofSize: Style.text * scale * zoom, weight: .bold)
    }

    /// CGImage малюється догори дриґом у системі з y вниз — тут його перевертаємо назад.
    private func draw(_ img: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private func draw(_ mark: Mark, _ ctx: CGContext) {
        let k = scale
        let white = NSColor.white.cgColor
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        switch mark {
        case let .arrow(a, b, ink):
            guard let path = Self.arrowPath(from: a, to: b, width: Style.arrow * k) else { return }
            ctx.addPath(path)
            ctx.setStrokeColor(white)
            ctx.setLineWidth(2 * Style.halo * k)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setFillColor(ink.color.cgColor)
            ctx.fillPath()
        case let .rect(r, ink):
            let path = CGPath(roundedRect: r, cornerWidth: 3 * k, cornerHeight: 3 * k, transform: nil)
            ctx.addPath(path)
            ctx.setStrokeColor(white)
            ctx.setLineWidth((Style.rect + 2 * Style.halo) * k)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setStrokeColor(ink.color.cgColor)
            ctx.setLineWidth(Style.rect * k)
            ctx.strokePath()
        case let .marker(points, ink):
            guard let first = points.first else { return }
            ctx.move(to: first)
            for p in points.dropFirst() { ctx.addLine(to: p) }
            // Множення кольорів: текст під маркером лишається чорним, а смуга — одним тоном,
            // навіть там, де вона перетинає сама себе.
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(ink.color.withAlphaComponent(Style.markerAlpha).cgColor)
            ctx.setLineWidth(Style.marker * k)
            ctx.strokePath()
        case let .text(s, p, ink):
            let font = textFont()
            let halo = NSAttributedString(string: s, attributes: [
                .font: font, .strokeColor: NSColor.white, .strokeWidth: 30,
            ])
            let body = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink.color])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            halo.draw(at: p)
            body.draw(at: p)
            NSGraphicsContext.restoreGraphicsState()
        case let .blur(r):
            ctx.clip(to: r)
            draw(pixelated, in: CGRect(origin: .zero, size: size), ctx)
        }
    }

    /// Стрілка одним контуром: тонкий хвіст, тіло завширшки `w`, наконечник зі скошеними вусами.
    static func arrowPath(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath? {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1 else { return nil }
        let d = CGPoint(x: dx / len, y: dy / len)
        let n = CGPoint(x: -d.y, y: d.x)
        let head = min(w * 4.5, len * 0.6)   // довжина наконечника
        let half = head * 0.55               // половина ширини наконечника
        func at(_ base: CGPoint, _ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: base.x + d.x * along + n.x * side, y: base.y + d.y * along + n.y * side)
        }
        let path = CGMutablePath()
        path.move(to: at(a, 0, w * 0.2))
        path.addLine(to: at(b, -head * 0.75, w / 2))
        path.addLine(to: at(b, -head, half))
        path.addLine(to: b)
        path.addLine(to: at(b, -head, -half))
        path.addLine(to: at(b, -head * 0.75, -w / 2))
        path.addLine(to: at(a, 0, -w * 0.2))
        path.closeSubpath()
        return path
    }

    // MARK: результат

    /// Готова картинка з позначками в повному розмірі знімка.
    func export(_ marks: [Mark]) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        render(marks, in: ctx)
        return ctx.makeImage()
    }

    /// Кладе картинку в буфер: PNG (його беруть браузери й чати) і TIFF (для старіших програм).
    @discardableResult
    func copy(_ marks: [Mark], to pasteboard: NSPasteboard = .general) -> Bool {
        guard let out = export(marks) else { return false }
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = NSSize(width: CGFloat(out.width) / scale, height: CGFloat(out.height) / scale)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation(using: .lzw, factor: 0) { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }
}

// MARK: - Тека зі знімками

/// Куди macOS кладе знімки. Панель ⌘⇧5 пише власний ключ `location-screenshot` (окремо від відео),
/// старий спосіб — `location`; нічого немає — робочий стіл.
func screenshotFolder() -> URL {
    for key in ["location-screenshot", "location"] {
        if let path = CFPreferencesCopyAppValue(key as CFString, "com.apple.screencapture" as CFString) as? String,
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
}

/// Усі PNG у теці, від старших до новіших. Приховані пропускаємо: система спершу пише
/// прихований тимчасовий файл і лише потім перейменовує його на «Знімок екрана…».
func screenshots(in dir: URL) -> [URL] {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey],
                                                  options: [.skipsHiddenFiles]) else { return [] }
    func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
    return items
        .filter { $0.pathExtension.lowercased() == "png" }
        .map { ($0, created($0)) }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
}
