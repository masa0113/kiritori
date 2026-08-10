import AppKit

enum SelectionMode {
    case region
    case window
}

enum SelectionResult {
    /// グローバル AppKit 座標(bottom-left 原点)の矩形と対象スクリーン
    case region(CGRect, NSScreen)
    case window(CGWindowID)
}

/// 全ディスプレイに透明オーバーレイを出して範囲/ウィンドウを選択させる
final class SelectionController {
    static let shared = SelectionController()

    private var windows: [NSWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    var isActive: Bool { !windows.isEmpty }

    func begin(mode: SelectionMode, completion: @escaping (SelectionResult?) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen, mode: mode)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    /// オーバーレイを閉じ、少し待ってから(合成が反映されてから)完了を呼ぶ
    func finish(_ result: SelectionResult?) {
        guard let done = completion else { return }
        completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if result != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done(result) }
        } else {
            done(nil)
        }
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, mode: SelectionMode) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = OverlayView(screen: screen, mode: mode)
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private let screen: NSScreen
    private let mode: SelectionMode

    private var dragStart: CGPoint?
    private var selectionRect: CGRect = .zero          // ビューローカル座標
    private var highlightRect: CGRect?                 // ビューローカル座標
    private var highlightWindowID: CGWindowID?

    init(screen: NSScreen, mode: SelectionMode) {
        self.screen = screen
        self.mode = mode
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if mode == .window { updateHighlight() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            SelectionController.shared.finish(nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if mode == .window { updateHighlight() }
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .region {
            dragStart = convert(event.locationInWindow, from: nil)
            selectionRect = .zero
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .window:
            if let id = highlightWindowID {
                SelectionController.shared.finish(.window(id))
            } else {
                SelectionController.shared.finish(nil)
            }
        case .region:
            defer { dragStart = nil }
            if selectionRect.width >= 4, selectionRect.height >= 4 {
                let global = selectionRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                SelectionController.shared.finish(.region(global, screen))
            } else if let info = WindowFinder.windowUnderCursor() {
                // ドラッグせずクリック → カーソル下のウィンドウを撮影
                SelectionController.shared.finish(.window(info.id))
            } else {
                SelectionController.shared.finish(nil)
            }
        }
    }

    private func updateHighlight() {
        if let info = WindowFinder.windowUnderCursor() {
            highlightWindowID = info.id
            highlightRect = info.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        } else {
            highlightWindowID = nil
            highlightRect = nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.25)

        if mode == .region, selectionRect.width > 0, selectionRect.height > 0 {
            let r = selectionRect
            dim.setFill()
            CGRect(x: 0, y: 0, width: bounds.width, height: r.minY).fill()
            CGRect(x: 0, y: r.maxY, width: bounds.width, height: max(0, bounds.height - r.maxY)).fill()
            CGRect(x: 0, y: r.minY, width: r.minX, height: r.height).fill()
            CGRect(x: r.maxX, y: r.minY, width: max(0, bounds.width - r.maxX), height: r.height).fill()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()

            drawSizeLabel(for: r)
        } else {
            dim.setFill()
            bounds.fill()
            if mode == .window, let h = highlightRect {
                NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
                h.fill()
                NSColor.controlAccentColor.setStroke()
                let p = NSBezierPath(rect: h.insetBy(dx: 1, dy: 1))
                p.lineWidth = 2
                p.stroke()
            }
        }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let padding: CGFloat = 5
        var origin = CGPoint(x: rect.maxX - size.width - padding * 2, y: rect.minY - size.height - padding * 2 - 4)
        if origin.y < 0 { origin.y = rect.minY + 4 }
        if origin.x < 0 { origin.x = rect.minX }
        let bg = CGRect(
            x: origin.x, y: origin.y,
            width: size.width + padding * 2, height: size.height + padding * 2
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: bg.minX + padding, y: bg.minY + padding), withAttributes: attrs)
    }
}

enum WindowFinder {
    struct WindowInfo {
        let id: CGWindowID
        let frame: CGRect  // グローバル AppKit 座標
    }

    /// カーソル直下にある通常ウィンドウ(前面優先)。自プロセスは除外。
    static func windowUnderCursor() -> WindowInfo? {
        let mouse = NSEvent.mouseLocation
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let myPID = Int32(ProcessInfo.processInfo.processIdentifier)
        // CG 座標(top-left 原点)→ AppKit 座標(bottom-left 原点)の変換基準
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width > 40, cgRect.height > 40,
                  let number = info[kCGWindowNumber as String] as? UInt32
            else { continue }

            let appKitRect = CGRect(
                x: cgRect.minX,
                y: primaryHeight - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
            if appKitRect.contains(mouse) {
                return WindowInfo(id: number, frame: appKitRect)
            }
        }
        return nil
    }
}
