import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var savePath = SettingsStore.shared.saveDirectory.path
    @State private var autoCopy = SettingsStore.shared.autoCopy
    @State private var autoSave = SettingsStore.shared.autoSave
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("保存") {
                LabeledContent("保存先") {
                    HStack {
                        Text(abbreviatedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("変更…") { chooseFolder() }
                    }
                }
            }

            Section("撮影後の動作") {
                Toggle("クリップボードへ自動コピー", isOn: $autoCopy)
                    .onChange(of: autoCopy) { _, v in SettingsStore.shared.autoCopy = v }
                Toggle("ファイルへ自動保存", isOn: $autoSave)
                    .onChange(of: autoSave) { _, v in SettingsStore.shared.autoSave = v }
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in toggleLoginItem(v) }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("ショートカット") {
                LabeledContent("範囲を選択して撮影", value: "⇧⌘7")
                LabeledContent("ウィンドウを撮影", value: "⇧⌘8")
                LabeledContent("全画面を撮影", value: "⇧⌘9")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var abbreviatedPath: String {
        (savePath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = SettingsStore.shared.saveDirectory
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            SettingsStore.shared.saveDirectory = url
            savePath = url.path
        }
    }

    private func toggleLoginItem(_ enable: Bool) {
        loginItemError = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = "設定できませんでした: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
