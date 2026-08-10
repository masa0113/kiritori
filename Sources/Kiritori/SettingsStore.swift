import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: "saveDirectory") {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { defaults.set(newValue.path, forKey: "saveDirectory") }
    }

    var autoCopy: Bool {
        get { defaults.object(forKey: "autoCopy") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCopy") }
    }

    var autoSave: Bool {
        get { defaults.object(forKey: "autoSave") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoSave") }
    }

    static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "スクリーンショット \(f.string(from: date)).png"
    }

    /// 保存先ディレクトリに新規ファイルとして書き出す
    @discardableResult
    func save(_ capture: Capture) -> URL? {
        let dir = saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName())
        guard let data = capture.pngData() else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
