import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = shared
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKeys()
    }

    // MARK: - メニューバー

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Kiritori"
            )
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(makeItem("範囲を選択して撮影", #selector(captureRegionAction), key: "7"))
        menu.addItem(makeItem("ウィンドウを撮影", #selector(captureWindowAction), key: "8"))
        menu.addItem(makeItem("全画面を撮影", #selector(captureScreenAction), key: "9"))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Kiritori を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        return item
    }

    private func registerHotKeys() {
        HotKeyManager.shared.register(id: 1, keyCode: 26 /* 7 */, modifiers: HotKeyManager.cmdShift) { [weak self] in
            self?.startCapture(.region)
        }
        HotKeyManager.shared.register(id: 2, keyCode: 28 /* 8 */, modifiers: HotKeyManager.cmdShift) { [weak self] in
            self?.startCapture(.window)
        }
        HotKeyManager.shared.register(id: 3, keyCode: 25 /* 9 */, modifiers: HotKeyManager.cmdShift) { [weak self] in
            self?.startCapture(.fullScreen)
        }
    }

    @objc private func captureRegionAction() { startCapture(.region) }
    @objc private func captureWindowAction() { startCapture(.window) }
    @objc private func captureScreenAction() { startCapture(.fullScreen) }

    // MARK: - 撮影フロー

    private enum CaptureKind {
        case region, window, fullScreen
    }

    private func startCapture(_ kind: CaptureKind) {
        guard !SelectionController.shared.isActive else { return }
        guard ensureScreenCapturePermission() else { return }

        switch kind {
        case .region:
            SelectionController.shared.begin(mode: .region) { [weak self] result in
                self?.process(result)
            }
        case .window:
            SelectionController.shared.begin(mode: .window) { [weak self] result in
                self?.process(result)
            }
        case .fullScreen:
            let screen = screenUnderMouse()
            Task { @MainActor in
                do {
                    let capture = try await CaptureEngine.captureDisplay(screen: screen)
                    self.handle(capture)
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    private func process(_ result: SelectionResult?) {
        guard let result else { return }
        Task { @MainActor in
            do {
                let capture: Capture
                switch result {
                case .region(let rect, let screen):
                    capture = try await CaptureEngine.captureRegion(rect: rect, on: screen)
                case .window(let id):
                    capture = try await CaptureEngine.captureWindow(windowID: id)
                }
                self.handle(capture)
            } catch {
                self.showError(error)
            }
        }
    }

    private func handle(_ capture: Capture) {
        if SettingsStore.shared.autoCopy {
            Clipboard.copy(capture)
        }
        if SettingsStore.shared.autoSave {
            SettingsStore.shared.save(capture)
        }
        QuickActionController.shared.show(capture)
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - 権限

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = """
        システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音 で \
        「Kiritori」を許可して、アプリを再起動してください。
        """
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "あとで")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "撮影に失敗しました"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - 設定

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Kiritori 設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
