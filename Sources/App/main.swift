// Помітка — значок у рядку меню. Стежить за текою знімків і відкриває кожен новий знімок на розмітку.
import AppKit
import ServiceManagement
import os

let log = Logger(subsystem: "local.pomitka", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let folder = screenshotFolder()
    /// Імена файлів, які вже бачили: знімки, що лежали до запуску, повторно не відкриваємо.
    private var seen = Set<String>()
    private var watch: DispatchSourceFileSystemObject?
    private var editors: [EditorWindow] = []
    private let defaults = UserDefaults.standard
    private let launchAgent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/local.pomitka.plist")

    /// «Відкривати одразу після знімка» — увімкнено, поки людина не вимкне в меню.
    private var autoOpen: Bool {
        get { !defaults.bool(forKey: "autoOpenOff") }
        set { defaults.set(!newValue, forKey: "autoOpenOff") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Помітка") {
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "✎"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        seen = Set(screenshots(in: folder).map(\.lastPathComponent))
        startWatching()

        // Без запуску при вході програма марна — вмикаємо один раз сами, далі вирішує людина в меню.
        if !defaults.bool(forKey: "loginSetUp") {
            defaults.set(true, forKey: "loginSetUp")
            if !loginEnabled() { toggleLogin() }
        }
        log.notice("стежу за \(self.folder.path, privacy: .public)")
    }

    // MARK: стеження за текою

    private func startWatching() {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("не відкрити теку \(self.folder.path, privacy: .public)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            // Дати системі дописати файл до кінця.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.checkFolder() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watch = src
    }

    private func checkFolder() {
        for url in screenshots(in: folder) where !seen.contains(url.lastPathComponent) {
            seen.insert(url.lastPathComponent)
            if autoOpen { open(url) }
        }
    }

    private func open(_ url: URL, attempt: Int = 0) {
        guard let canvas = Canvas(contentsOf: url) else {
            // Файл міг ще дописуватись — пробуємо ще кілька разів.
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.open(url, attempt: attempt + 1) }
            } else {
                log.error("не прочитати \(url.lastPathComponent, privacy: .public)")
            }
            return
        }
        show(canvas, title: url.deletingPathExtension().lastPathComponent)
    }

    private func show(_ canvas: Canvas, title: String) {
        // Вікно — на тому екрані, де зараз курсор: там людина щойно робила знімок.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let editor = EditorWindow(canvas: canvas, title: title, screen: screen)
        editor.onFinish = { [weak self] e in
            guard let self else { return }
            editors.removeAll { $0 === e }
            // Остання розмітка закрита — фокус повертається туди, де людина була до знімка.
            if editors.isEmpty { NSApp.hide(nil) }
        }
        editors.append(editor)
        editor.present()
        log.notice("відкрито: \(title, privacy: .public)")
    }

    // MARK: меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Розмітити останній знімок", #selector(openLatest)).isEnabled = !screenshots(in: folder).isEmpty
        add("Розмітити картинку з буфера", #selector(openPasteboard)).isEnabled =
            NSImage.canInit(with: NSPasteboard.general)
        add("Відкрити картинку…", #selector(openFile))
        menu.addItem(.separator())
        add("Відкривати одразу після знімка", #selector(toggleAuto)).state = autoOpen ? .on : .off
        add("Запускати при вході в систему", #selector(toggleLogin)).state = loginEnabled() ? .on : .off
        add("Показати теку зі знімками", #selector(showFolder))
        menu.addItem(.separator())
        add("Вийти з Помітки", #selector(quit))
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc func openLatest() {
        if let url = screenshots(in: folder).last { open(url) }
    }

    @objc func openPasteboard() {
        if let canvas = Canvas(pasteboard: .general) { show(canvas, title: "Картинка з буфера") }
    }

    @objc func openFile() {
        activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let canvas = Canvas(contentsOf: url) {
            show(canvas, title: url.deletingPathExtension().lastPathComponent)
        } else {
            alert("Не вдалося відкрити \(url.lastPathComponent)")
        }
    }

    @objc func toggleAuto() { autoOpen.toggle() }

    @objc func showFolder() { NSWorkspace.shared.open(folder) }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: запуск при вході — SMAppService; якщо підпис його не влаштує, звичайний агент launchd

    private func loginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled || FileManager.default.fileExists(atPath: launchAgent.path)
    }

    @objc func toggleLogin() {
        if loginEnabled() {
            try? SMAppService.mainApp.unregister()
            try? FileManager.default.removeItem(at: launchAgent)
            return
        }
        do {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                alert("Дозволь Помітку в «Системні параметри → Загальні → Обʼєкти входу».")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let agent: [String: Any] = [
                "Label": "local.pomitka",
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            do {
                try FileManager.default.createDirectory(at: launchAgent.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let raw = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
                try raw.write(to: launchAgent, options: .atomic)
            } catch {
                alert("Не вдалося увімкнути запуск при вході: \(error.localizedDescription)")
            }
        }
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    private func alert(_ text: String) {
        activate()
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
