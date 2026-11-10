// Помітка — вікно розмітки: смуга інструментів угорі, під нею полотно зі знімком.
import AppKit

// MARK: - Полотно

/// Показує знімок і позначки; мишею малює нові.
final class EditorView: NSView, NSTextFieldDelegate {
    let canvas: Canvas
    private(set) var marks: [Mark] = []
    private var draft: Mark?
    private(set) var tool: Tool = .arrow
    /// Кожен інструмент памʼятає свій колір і товщину: маркер жовтий, решта червоні.
    private var pens = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, Pen(ink: $0.defaultInk)) })
    var pen: Pen { pens[tool] ?? Pen(ink: tool.defaultInk) }

    var onChange: () -> Void = {}
    var onCopy: () -> Void = {}
    var onClose: () -> Void = {}
    var onTool: (Tool) -> Void = { _ in }
    var onStep: (Int) -> Void = { _ in }

    private var start = CGPoint.zero
    private var points: [CGPoint] = []
    private var field: NSTextField?
    private var fieldOrigin = CGPoint.zero
    private var fieldPen = Pen(ink: .red)
    var isEditingText: Bool { field != nil }

    init(canvas: Canvas, size: NSSize) {
        self.canvas = canvas
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("не використовується") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// Перший клік у неактивному вікні одразу малює, а не лише робить вікно активним.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Скільки пунктів вікна припадає на один піксель знімка.
    private var zoom: CGFloat { bounds.width / canvas.size.width }

    func setTool(_ t: Tool) {
        commitText()
        tool = t
        window?.invalidateCursorRects(for: self)
    }

    func setInk(_ i: Ink) {
        var p = pen   // окремою копією: читати pen під час запису в pens не можна
        p.ink = i
        pens[tool] = p
        if let f = field {
            fieldPen.ink = i
            f.textColor = i.color
        }
    }

    func setSize(_ s: Size) {
        var p = pen   // окремою копією: читати pen під час запису в pens не можна
        p.size = s
        pens[tool] = p
        if let f = field {
            fieldPen.size = s
            f.font = canvas.textFont(s, zoom: zoom)
            controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            f.frame.size.height = f.fittingSize.height
        }
    }

    func append(_ mark: Mark) {
        marks.append(mark)
        onChange()
        needsDisplay = true
    }

    /// ⌘Z: спершу скасовує недописаний текст, далі — останню позначку.
    func undo() {
        if field != nil { dropText(); return }
        guard !marks.isEmpty else { return }
        marks.removeLast()
        onChange()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: zoom, y: zoom)
        canvas.render(draft.map { marks + [$0] } ?? marks, in: ctx)
        ctx.restoreGState()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    // MARK: миша

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x / zoom, 0), canvas.size.width),
                       y: min(max(p.y / zoom, 0), canvas.size.height))
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = imagePoint(event)
        start = p
        switch tool {
        case .text: beginText(at: p)
        case .marker:
            points = [p]
            draft = .marker(points, pen: pen)
        default: draft = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        switch tool {
        case .arrow: draft = .arrow(from: start, to: p, pen: pen)
        case .rect: draft = .rect(rectBetween(start, p), pen: pen)
        case .blur: draft = .blur(rectBetween(start, p))
        case .marker:
            // Із Shift — рівна лінія: так зручно провести по рядку тексту.
            if event.modifierFlags.contains(.shift) { points = [start, p] } else { points.append(p) }
            draft = .marker(points, pen: pen)
        case .text: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let d = draft, d.isVisible(minSize: 3 * canvas.scale) { append(d) }
        draft = nil
        needsDisplay = true
    }

    // MARK: клавіші

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCopy()      // Return, Enter на цифровому блоці
        case 53: onClose()         // Esc
        default:
            // Цифри 1…5 — інструменти; беремо фізичні клавіші, щоб працювало і в українській розкладці.
            let digits: [UInt16: Tool] = [18: .arrow, 19: .rect, 20: .marker, 21: .text, 23: .blur]
            if let t = digits[event.keyCode] {
                onTool(t)
            } else if event.keyCode == 33 || event.keyCode == 30 {
                onStep(event.keyCode == 33 ? -1 : 1)   // [ — тонше, ] — товще (фізичні клавіші)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: текст

    private func beginText(at p: CGPoint) {
        let f = NSTextField(string: "")
        f.font = canvas.textFont(pen.size, zoom: zoom)
        f.textColor = pen.ink.color
        f.isBordered = false
        f.drawsBackground = true
        f.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        f.focusRingType = .none
        f.placeholderString = "Текст, потім Enter"
        f.delegate = self
        f.target = self
        f.action = #selector(commitText)
        f.sizeToFit()
        f.frame = NSRect(x: p.x * zoom - 2, y: p.y * zoom, width: max(f.frame.width, 160), height: f.frame.height)
        addSubview(f)
        window?.makeFirstResponder(f)
        field = f
        fieldOrigin = p
        fieldPen = pen
    }

    /// Поле росте разом із текстом.
    func controlTextDidChange(_ note: Notification) {
        guard let f = field else { return }
        let w = f.attributedStringValue.size().width + 24
        f.frame.size.width = max(160, min(w, bounds.width - f.frame.minX))
    }

    /// Esc у полі — прибрати недописаний текст, а не закрити вікно.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        dropText()
        return true
    }

    /// Enter, клік повз поле або інший інструмент — текст стає позначкою.
    @objc func commitText() {
        guard let f = field else { return }
        field = nil   // до removeFromSuperview: воно ще раз викличе цю дію
        let s = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
        if !s.isEmpty { append(.text(s, at: fieldOrigin, pen: fieldPen)) }
    }

    private func dropText() {
        guard let f = field else { return }
        field = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
    }
}

// MARK: - Вікно

/// Вікно перехоплює ⌘-клавіші за ФІЗИЧНИМИ кодами: в українській розкладці ⌘C приходить як «⌘с»,
/// і звичайне меню його б не впізнало. Під час набору тексту ⌘C/⌘V/⌘X/⌘A/⌘Z ідуть у поле.
final class EditorWindowFrame: NSWindow {
    weak var editor: EditorView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Лише значущі клавіші: з увімкненим Caps Lock ⌘C має працювати так само.
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
              let editor else { return super.performKeyEquivalent(with: event) }
        let edit: [UInt16: Selector] = [
            8: #selector(NSText.copy(_:)), 9: #selector(NSText.paste(_:)), 7: #selector(NSText.cut(_:)),
            0: #selector(NSText.selectAll(_:)), 6: Selector(("undo:")),
        ]
        if editor.isEditingText, let action = edit[event.keyCode] {
            return NSApp.sendAction(action, to: nil, from: self)
        }
        switch event.keyCode {
        case 8: editor.onCopy(); return true          // ⌘C
        case 6: editor.undo(); return true            // ⌘Z
        case 13: performClose(nil); return true       // ⌘W
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Вікно розмітки одного знімка.
final class EditorWindow: NSWindowController, NSWindowDelegate {
    let editor: EditorView
    private let tools = NSSegmentedControl()
    private let colors = NSSegmentedControl()
    private let sizes = NSSegmentedControl()
    private let undoButton = NSButton(title: "Крок назад", target: nil, action: nil)
    private let copyButton = NSButton(title: "Копіювати", target: nil, action: nil)
    private var copied = false
    /// Вікно закрилось — програма прибирає його зі списку.
    var onFinish: (EditorWindow) -> Void = { _ in }

    init(canvas: Canvas, title: String, screen: NSScreen?) {
        // Знімок у пунктах; більший за екран — зменшуємо, менший — показуємо 1:1.
        let pt = NSSize(width: canvas.size.width / canvas.scale, height: canvas.size.height / canvas.scale)
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fit = min(1, area.width * 0.92 / pt.width, (area.height * 0.92 - 90) / pt.height)
        let viewSize = NSSize(width: (pt.width * fit).rounded(), height: (pt.height * fit).rounded())
        editor = EditorView(canvas: canvas, size: viewSize)

        let window = EditorWindowFrame(contentRect: NSRect(origin: .zero, size: viewSize),
                                       styleMask: [.titled, .closable, .miniaturizable],
                                       backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.editor = editor
        super.init(window: window)
        window.delegate = self

        buildBar()
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        bar.setViews([tools, colors, sizes], in: .leading)
        let hint = NSTextField(labelWithString: "⏎ — копіювати й закрити   Esc — закрити")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        bar.setViews([hint, undoButton, copyButton], in: .trailing)

        // Під знімком — темніше тло: якщо знімок вужчий за смугу, він стоїть посередині.
        let holder = NSView()
        holder.wantsLayer = true
        holder.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        holder.addSubview(editor)
        let content = NSView()
        content.addSubview(bar)
        content.addSubview(holder)
        for v in [bar, holder, editor] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            holder.topAnchor.constraint(equalTo: bar.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            holder.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            editor.widthAnchor.constraint(equalToConstant: viewSize.width),
            editor.heightAnchor.constraint(equalToConstant: viewSize.height),
            editor.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            editor.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            holder.widthAnchor.constraint(greaterThanOrEqualTo: editor.widthAnchor),
            holder.heightAnchor.constraint(greaterThanOrEqualTo: editor.heightAnchor),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))

        editor.onChange = { [weak self] in self?.syncButtons() }
        editor.onCopy = { [weak self] in self?.copyAndClose() }
        editor.onClose = { [weak self] in self?.window?.performClose(nil) }
        editor.onTool = { [weak self] t in self?.choose(t) }
        editor.onStep = { [weak self] d in self?.step(d) }
        syncButtons()
    }

    required init?(coder: NSCoder) { fatalError("не використовується") }

    private func buildBar() {
        tools.segmentCount = Tool.allCases.count
        tools.trackingMode = .selectOne
        for t in Tool.allCases {
            tools.setLabel(t.title, forSegment: t.rawValue)
            tools.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: t.rawValue)
            tools.setImageScaling(.scaleProportionallyDown, forSegment: t.rawValue)
            tools.setToolTip("\(t.title) — клавіша \(t.rawValue + 1)", forSegment: t.rawValue)
        }
        tools.target = self
        tools.action = #selector(pickTool)

        colors.segmentCount = Ink.allCases.count
        colors.trackingMode = .selectOne
        for i in Ink.allCases {
            colors.setImage(Self.dot(i.color), forSegment: i.rawValue)
            colors.setWidth(30, forSegment: i.rawValue)
            colors.setToolTip(i.title, forSegment: i.rawValue)
        }
        colors.target = self
        colors.action = #selector(pickInk)

        sizes.segmentCount = Size.allCases.count
        sizes.trackingMode = .selectOne
        for s in Size.allCases {
            sizes.setImage(Self.line(s), forSegment: s.rawValue)
            sizes.setWidth(30, forSegment: s.rawValue)
            sizes.setToolTip("\(s.title) — клавіші [ і ]", forSegment: s.rawValue)
        }
        sizes.target = self
        sizes.action = #selector(pickSize)

        undoButton.target = self
        undoButton.action = #selector(undo)
        undoButton.toolTip = "Прибрати останню позначку — ⌘Z"
        copyButton.target = self
        copyButton.action = #selector(copyAndClose)
        copyButton.bezelColor = .controlAccentColor
        copyButton.toolTip = "Скопіювати в буфер і закрити — ⏎ або ⌘C"
        choose(.arrow)
    }

    /// Кольоровий кружечок для кнопки палітри.
    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    /// Значок товщини: риска, товща з кожним кроком.
    private static func line(_ s: Size) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            let h = 2 + CGFloat(s.rawValue) * 2.5
            NSBezierPath(roundedRect: NSRect(x: 1, y: (rect.height - h) / 2, width: 14, height: h),
                         xRadius: h / 2, yRadius: h / 2).fill()
            return true
        }
        image.isTemplate = true   // колір бере з теми: світла чи темна
        return image
    }

    private func choose(_ t: Tool) {
        editor.setTool(t)
        tools.selectedSegment = t.rawValue
        colors.selectedSegment = editor.pen.ink.rawValue
        sizes.selectedSegment = editor.pen.size.rawValue
        colors.isEnabled = t != .blur
        sizes.isEnabled = t != .blur
    }

    /// [ і ] — тонше / товще для поточного інструмента.
    private func step(_ delta: Int) {
        guard editor.tool != .blur, let s = Size(rawValue: editor.pen.size.rawValue + delta) else { return }
        editor.setSize(s)
        sizes.selectedSegment = s.rawValue
    }

    private func syncButtons() { undoButton.isEnabled = !editor.marks.isEmpty }

    @objc private func pickTool() {
        guard let t = Tool(rawValue: tools.selectedSegment) else { return }
        choose(t)
        window?.makeFirstResponder(editor)
    }

    @objc private func pickInk() {
        guard let i = Ink(rawValue: colors.selectedSegment) else { return }
        editor.setInk(i)
    }

    @objc private func pickSize() {
        guard let s = Size(rawValue: sizes.selectedSegment) else { return }
        editor.setSize(s)
        window?.makeFirstResponder(editor)
    }

    @objc private func undo() { editor.undo() }

    @objc private func copyAndClose() {
        editor.commitText()
        guard editor.canvas.copy(editor.marks) else {
            NSSound.beep()
            return
        }
        copied = true
        window?.close()
    }

    /// Показати вікно. З фону macOS може не віддати фокус, тому вікно спершу «плаває» над усіма,
    /// а звичайним стає, щойно отримає фокус.
    func present() {
        guard let w = window else { return }
        w.level = .floating
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        w.makeFirstResponder(editor)
    }

    func windowDidBecomeKey(_ notification: Notification) { window?.level = .normal }

    /// Закрити без копіювання, коли вже щось намальовано, — лише після підтвердження.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editor.commitText()   // недописаний підпис — теж позначка, яку шкода втратити
        guard !copied, !editor.marks.isEmpty else { return true }
        let a = NSAlert()
        a.messageText = "Закрити без копіювання?"
        a.informativeText = "Позначки зникнуть. Сам знімок лишиться в теці."
        a.addButton(withTitle: "Закрити")
        a.addButton(withTitle: "Повернутись")
        return a.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) { onFinish(self) }
}
