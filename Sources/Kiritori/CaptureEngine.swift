import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "対象のディスプレイが見つかりませんでした。"
        case .windowNotFound: return "対象のウィンドウが見つかりませんでした。画面収録の許可を確認してください。"
        }
    }
}

enum CaptureEngine {

    /// 画面全体(指定スクリーン)
    static func captureDisplay(screen: NSScreen) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try display(for: screen, in: content)
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
        let scale = CGFloat(filter.pointPixelScale)
        let config = baseConfig()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(cgImage: image, scale: scale)
    }

    /// 範囲指定(rect はグローバル AppKit 座標・bottom-left 原点)
    static func captureRegion(rect: CGRect, on screen: NSScreen) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try display(for: screen, in: content)
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
        let scale = CGFloat(filter.pointPixelScale)

        // ディスプレイ内ローカル座標(top-left 原点)へ変換
        let sf = screen.frame
        let local = CGRect(
            x: rect.minX - sf.minX,
            y: sf.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let config = baseConfig()
        config.sourceRect = local
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(cgImage: image, scale: scale)
    }

    /// 単一ウィンドウ
    static func captureWindow(windowID: CGWindowID) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = baseConfig()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(cgImage: image, scale: scale)
    }

    // MARK: - private

    private static func baseConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        return config
    }

    private static func display(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == CGDirectDisplayID(number.uint32Value) })
        else {
            throw CaptureError.displayNotFound
        }
        return display
    }

    /// 自アプリのウィンドウ(オーバーレイやパネル)を撮影対象から除外する
    private static func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows.filter { $0.owningApplication?.processID == pid }
    }
}
