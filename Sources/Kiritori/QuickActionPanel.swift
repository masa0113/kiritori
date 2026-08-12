import AppKit
import SwiftUI

/// 撮影直後に画面左下へ出るフローティングパネル
final class QuickActionController {
    static let shared = QuickActionController()

    private var panel: NSPanel?
    private var timer: Timer?
    private var isHovering = false

    func show(_ capture: Capture) {
        close()

        // ドラッグ&ドロップ用に一時ファイルを書き出しておく
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(SettingsStore.fileName())
        try? capture.pngData()?.write(to: tempURL)

        let view = QuickActionView(
            capture: capture,
            dragURL: tempURL,
            onCopy: { [weak self] in
                Clipboard.copy(capture)
                self?.close()
            },
            onSave: { [weak self] in
                SettingsStore.shared.save(capture)
                self?.close()
            },
            onEdit: { [weak self] in
                self?.close()
                Task { @MainActor in
                    EditorWindowController.open(capture)
                }
            },
            onClose: { [weak self] in
                self?.close()
            },
            onHover: { [weak self] hovering in
                self?.isHovering = hovering
                if hovering {
                    self?.timer?.invalidate()
                } else {
                    self?.scheduleClose(after: 3)
                }
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: vf.minX + 12, y: vf.minY + 12))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        scheduleClose(after: 8)
    }

    func close() {
        timer?.invalidate()
        timer = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func scheduleClose(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, !self.isHovering else { return }
            self.close()
        }
    }
}

private struct QuickActionView: View {
    let capture: Capture
    let dragURL: URL
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    private var thumbSize: CGSize {
        let s = capture.pointSize
        let scale = min(280 / max(s.width, 1), 180 / max(s.height, 1), 1)
        return CGSize(width: max(s.width * scale, 60), height: max(s.height * scale, 40))
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(decorative: capture.cgImage, scale: capture.scale)
                .resizable()
                .frame(width: thumbSize.width, height: thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
                .onDrag { NSItemProvider(contentsOf: dragURL) ?? NSItemProvider() }

            HStack(spacing: 4) {
                actionButton("doc.on.doc", "コピー", action: onCopy)
                actionButton("square.and.arrow.down", "保存", action: onSave)
                actionButton("pencil.tip.crop.circle", "編集", action: onEdit)
                actionButton("xmark", "閉じる", action: onClose)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
        .padding(14)
        .onHover(perform: onHover)
    }

    private func actionButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
