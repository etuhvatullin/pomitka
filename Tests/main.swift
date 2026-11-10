// Перевірка Помітки без екрана: малює всі пʼять позначок на штучному знімку, читає пікселі,
// перевіряє буфер обміну (на окремій дошці, не на загальній), пошук нових знімків і вигляд вікна.
// Картинки для очей: build/sample.png (результат) і build/window.png (вікно розмітки).
import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ✓ \(what)" : "  ✗ \(what)")
    if !ok { failures += 1 }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build")

// MARK: штучний знімок 600×400 пт на «Retina» (1200×800 пікселів)

func makeShot() -> CGImage {
    let w = 1200, h = 800
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let font = NSFont.systemFont(ofSize: 40)
    let lines = ["Замовлення № 123456", "Пароль: secret-42", "Сума: 1 299 грн", "Статус: виконано"]
    for (i, s) in lines.enumerated() {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.black])
            .draw(at: CGPoint(x: 80, y: 100 + i * 120))
    }
    NSColor(srgbRed: 0.2, green: 0.3, blue: 0.4, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 820, y: 560, width: 300, height: 180)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// Пікселі картинки в sRGB, рядок 0 — верхній.
struct Pixels {
    let w: Int, h: Int
    let data: [UInt8]
    init(_ img: CGImage) {
        w = img.width
        h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        data = buf
    }
    func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * w + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
    func count(in r: CGRect, where test: ((r: Int, g: Int, b: Int)) -> Bool) -> Int {
        var n = 0
        for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) where test(at(x, y)) { n += 1 } }
        return n
    }
}

func writePNG(_ img: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
}

let shot = makeShot()
let canvas = Canvas(image: shot, scale: 2)
let hidden = CGRect(x: 70, y: 210, width: 480, height: 80)   // рядок «Пароль»
let marks: [Mark] = [
    .marker([CGPoint(x: 70, y: 130), CGPoint(x: 700, y: 130)], pen: Pen(ink: .yellow)),
    .blur(hidden),
    .arrow(from: CGPoint(x: 300, y: 720), to: CGPoint(x: 700, y: 450), pen: Pen(ink: .red)),
    .rect(CGRect(x: 60, y: 320, width: 520, height: 90), pen: Pen(ink: .blue)),
    .text("Перевір суму", at: CGPoint(x: 760, y: 380), pen: Pen(ink: .green)),
]

print("Малювання")
let result = canvas.export(marks)!
writePNG(result, "sample.png")
let px = Pixels(result), orig = Pixels(shot)
check(result.width == 1200 && result.height == 800, "розмір результату = розмір знімка")
let mid = px.at(500, 585)   // середина стрілки
check(mid.r > 180 && mid.g < 90 && mid.b < 90, "стрілка червона посередині \(mid)")
let side = px.at(60, 365)   // ліва сторона рамки
check(side.b > 180 && side.r < 100, "рамка синя на лівому боці \(side)")
let mark = px.at(690, 130)  // маркер на білому тлі, правіше за текст
check(mark.r > 230 && mark.g > 200 && mark.b < 150, "маркер жовтий на білому \(mark)")
let darkInMarker = px.count(in: CGRect(x: 80, y: 110, width: 300, height: 40)) { $0.r + $0.g + $0.b < 150 }
check(darkInMarker > 100, "текст під маркером лишився чорним (\(darkInMarker) темних пікселів)")
let darkBefore = orig.count(in: hidden) { $0.r + $0.g + $0.b < 150 }
let darkAfter = px.count(in: hidden) { $0.r + $0.g + $0.b < 150 }
check(darkBefore > 200 && darkAfter == 0, "«Сховати» прибрало літери пароля (\(darkBefore) → \(darkAfter) темних)")
let a = px.at(101, 241), b = px.at(118, 258)   // один квадрат 20×20
check(abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) <= 6, "«Сховати» — суцільні квадрати \(a) \(b)")
let green = px.count(in: CGRect(x: 760, y: 380, width: 360, height: 60)) { $0.g > 120 && $0.r < 90 && $0.b < 130 }
check(green > 200, "текст зелений на своєму місці (\(green) пікселів)")
check(px.at(1180, 20) == (255, 255, 255), "поза позначками знімок не змінився")
let box = px.at(900, 700)
check(abs(box.r - 51) < 4 && abs(box.b - 102) < 4, "кольори знімка не зсунулись \(box)")

let around = px.count(in: CGRect(x: 490, y: 575, width: 20, height: 20)) { $0.r + $0.g + $0.b < 200 }
check(around > 10, "у стрілки темний контур (\(around) темних пікселів біля тіла)")

print("Товщина")
func markerHeight(_ size: Size) -> Int {
    let img = canvas.export([.marker([CGPoint(x: 600, y: 600), CGPoint(x: 780, y: 600)], pen: Pen(ink: .yellow, size: size))])!
    return Pixels(img).count(in: CGRect(x: 700, y: 540, width: 1, height: 120)) { $0.b < 200 }
}
let thin = markerHeight(.thin), thick = markerHeight(.thick)
check(abs(thin - 22) <= 2 && abs(thick - 58) <= 2, "маркер: тонкий \(thin) пікс., товстий \(thick) пікс. (очікую ≈22 і ≈58)")
let bigText = canvas.textFont(.thick).pointSize, smallText = canvas.textFont(.thin).pointSize
check(bigText > smallText * 2.5, "текст: товстий \(bigText) проти тонкого \(smallText)")

print("Дрібниці")
check(!Mark.arrow(from: .zero, to: CGPoint(x: 2, y: 2), pen: Pen(ink: .red)).isVisible(minSize: 6), "клік без руху — не стрілка")
check(!Mark.marker([.zero], pen: Pen(ink: .yellow)).isVisible(minSize: 6), "маркер з однієї точки не лишається")
check(rectBetween(CGPoint(x: 10, y: 50), CGPoint(x: 4, y: 20)) == CGRect(x: 4, y: 20, width: 6, height: 30),
      "рамку можна тягнути в будь-який бік")

print("Масштаб із файлу")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pomitka-test-\(getpid())")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let retina = NSBitmapImageRep(cgImage: shot)
retina.size = NSSize(width: 600, height: 400)   // 144 DPI, як пише macOS для Retina
try! retina.representation(using: .png, properties: [:])!.write(to: tmp.appendingPathComponent("a.png"))
check(Canvas(contentsOf: tmp.appendingPathComponent("a.png"))?.scale == 2, "знімок з Retina → масштаб 2")
let plain = NSBitmapImageRep(cgImage: shot)
try! plain.representation(using: .png, properties: [:])!.write(to: tmp.appendingPathComponent("b.png"))
check(Canvas(contentsOf: tmp.appendingPathComponent("b.png"))?.scale == 1, "звичайний знімок → масштаб 1")

print("Нові знімки в теці")
FileManager.default.createFile(atPath: tmp.appendingPathComponent(".Знімок екрана тимчасовий.png").path, contents: Data())
FileManager.default.createFile(atPath: tmp.appendingPathComponent("Запис екрана.mov").path, contents: Data())
let names = screenshots(in: tmp).map(\.lastPathComponent)
check(names == ["a.png", "b.png"], "лише PNG, без прихованих і відео: \(names)")

print("Буфер обміну (окрема дошка)")
let board = NSPasteboard(name: NSPasteboard.Name("local.pomitka.selftest"))
check(canvas.copy(marks, to: board), "копіювання вдалось")
let pasted = board.data(forType: .png).flatMap { NSBitmapImageRep(data: $0) }
check(pasted?.pixelsWide == 1200 && pasted?.pixelsHigh == 800, "у буфері PNG повного розміру")
check(pasted.map { abs($0.size.width - 600) < 1 } == true, "у буфері розмір у пунктах, як у знімка")
check(board.data(forType: .tiff) != nil, "у буфері є й TIFF")
board.releaseGlobally()
try? FileManager.default.removeItem(at: tmp)

print("Вікно")
_ = NSApplication.shared
let window = EditorWindow(canvas: canvas, title: "Знімок екрана — перевірка", screen: nil)
for m in marks { window.editor.append(m) }
if let view = window.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("window.png"))
    check(view.bounds.width >= window.editor.bounds.width, "смуга інструментів не вужча за знімок")
}
// Курсор маркера — коло завширшки зі смугу: товстий маркер на «Retina» = 18 пт × 1,6 × 2 пікс. × масштаб вікна.
window.editor.setTool(.marker)
window.editor.setSize(.thick)
let zoomed = window.editor.bounds.width / canvas.size.width
check(abs(window.editor.brushDiameter - 18 * 1.6 * 2 * zoomed) < 0.01,
      "курсор маркера завширшки зі смугу (\(window.editor.brushDiameter) пт)")
// Малий знімок: вікно не стискається вужче за смугу інструментів.
let tiny = EditorWindow(canvas: Canvas(image: shot.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 100))!, scale: 2),
                        title: "малий", screen: nil)
let tinyWidth = tiny.window?.contentView?.bounds.width ?? 0
check(tinyWidth > 500, "вікно малого знімка вміщає всі кнопки (\(Int(tinyWidth)) пт)")

print(failures == 0 ? "Усе гаразд" : "Помилок: \(failures)")
exit(failures == 0 ? 0 : 1)
