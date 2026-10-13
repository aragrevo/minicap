import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let recorder = Recorder()
    private var options = Recorder.Options()
    private var hotKey: HotKey?
    private var startedAt: Date?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard
        if d.object(forKey: "fps") != nil { options.fps = d.integer(forKey: "fps") }
        if d.object(forKey: "mic") != nil { options.microphone = d.bool(forKey: "mic") }
        if d.object(forKey: "sys") != nil { options.systemAudio = d.bool(forKey: "sys") }
        if d.object(forKey: "cursor") != nil { options.showCursor = d.bool(forKey: "cursor") }

        recorder.onFinish = { [weak self] result in
            DispatchQueue.main.async { self?.finished(result) }
        }
        // ⌥⌘R inicia o detiene la grabación desde cualquier app.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            DispatchQueue.main.async { self?.toggle() }
        }
        refresh()
    }

    // MARK: Acciones

    @objc private func toggle() {
        if recorder.isRecording {
            Task { await recorder.stop() }
            stopTimer()
            refresh()
        } else {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await recorder.start(options: options)
                    startedAt = Date()
                    // Solo actualiza el reloj una vez por segundo y con tolerancia
                    // amplia, para que el sistema pueda agrupar los despertares.
                    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.refresh() }
                    }
                    t.tolerance = 0.5
                    RunLoop.main.add(t, forMode: .common)
                    timer = t
                } catch {
                    alert("No se pudo iniciar la grabación", error.localizedDescription)
                }
                refresh()
            }
        }
    }

    private func finished(_ result: Result<URL, Error>) {
        stopTimer()
        refresh()
        switch result {
        case .success(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(let error): alert("La grabación falló", error.localizedDescription)
        }
    }

    @objc private func setFPS(_ sender: NSMenuItem) { options.fps = sender.tag; save() }
    @objc private func toggleMic() { options.microphone.toggle(); save() }
    @objc private func toggleSys() { options.systemAudio.toggle(); save() }
    @objc private func toggleCursor() { options.showCursor.toggle(); save() }
    @objc private func openFolder() { NSWorkspace.shared.open(Recorder.folder) }

    private func save() {
        let d = UserDefaults.standard
        d.set(options.fps, forKey: "fps")
        d.set(options.microphone, forKey: "mic")
        d.set(options.systemAudio, forKey: "sys")
        d.set(options.showCursor, forKey: "cursor")
        refresh()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
    }

    // MARK: UI

    private func refresh() {
        let recording = recorder.isRecording
        let button = statusItem.button!
        button.image = NSImage(systemSymbolName: recording ? "stop.circle.fill" : "record.circle",
                               accessibilityDescription: "MiniCap")
        button.contentTintColor = recording ? .systemRed : nil
        if let startedAt {
            let s = Int(Date().timeIntervalSince(startedAt))
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.title = String(format: " %d:%02d", s / 60, s % 60)
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
        }
        statusItem.menu = buildMenu(recording: recording)
    }

    private func buildMenu(recording: Bool) -> NSMenu {
        let menu = NSMenu()
        let main = NSMenuItem(title: recording ? "Detener grabación" : "Grabar pantalla",
                              action: #selector(toggle), keyEquivalent: "r")
        main.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(main)
        menu.addItem(.separator())

        let settings: [(String, Bool, Selector)] = [
            ("Micrófono", options.microphone, #selector(toggleMic)),
            ("Audio del sistema", options.systemAudio, #selector(toggleSys)),
            ("Mostrar cursor", options.showCursor, #selector(toggleCursor)),
        ]
        for (title, on, sel) in settings {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.state = on ? .on : .off
            item.isEnabled = !recording
            menu.addItem(item)
        }

        let fpsMenu = NSMenu()
        for fps in [15, 30, 60] {
            let item = NSMenuItem(title: "\(fps) fps", action: #selector(setFPS(_:)), keyEquivalent: "")
            item.tag = fps
            item.state = options.fps == fps ? .on : .off
            fpsMenu.addItem(item)
        }
        let fpsItem = NSMenuItem(title: "Fotogramas por segundo", action: nil, keyEquivalent: "")
        fpsItem.submenu = fpsMenu
        fpsItem.isEnabled = !recording
        menu.addItem(fpsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Abrir carpeta de grabaciones", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        for item in fpsMenu.items { item.target = self }
        return menu
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
