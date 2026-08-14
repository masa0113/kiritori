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

    /// 実際に ScreenCaptureKit を呼んで画面収録権限を確認する。
    /// CGPreflightScreenCaptureAccess は新しい macOS で誤って false を返すことが
    /// あるため使わない。権限が未決定の場合はこの呼び出しが OS の許可プロンプトを出す。
    static func verifyAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

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
        // 切り出し範囲をピクセル境界に揃える。小数座標のまま渡すと
        // サンプリング位置がピクセル格子とずれて画像全体が滲む
        let px = CGRect(
            x: (local.minX * scale).rounded(),
            y: (local.minY * scale).rounded(),
            width: (local.width * scale).rounded(),
            height: (local.height * scale).rounded()
        )
        let config = baseConfig()
        config.sourceRect = CGRect(
            x: px.minX / scale,
            y: px.minY / scale,
            width: px.width / scale,
            height: px.height / scale
        )
        config.width = Int(px.width)
        config.height = Int(px.height)
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
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(cgImage: image, scale: scale)
    }

    // MARK: - private

    private static func baseConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best  // 常にネイティブ(Retina)解像度で取得
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
