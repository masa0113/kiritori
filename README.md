# Kiritori(切り取り)

CleanShot X ライクな macOS スクリーンショットツール。メニューバー常駐の自分用アプリ。

## 機能

- **範囲を選択して撮影** `⇧⌘7` — ドラッグで範囲選択(サイズ表示付き)。クリックだけならカーソル下のウィンドウを撮影
- **ウィンドウを撮影** `⇧⌘8` — ウィンドウをハイライト表示してクリックで撮影
- **全画面を撮影** `⇧⌘9` — マウスがあるディスプレイ全体
- **クイックアクションパネル** — 撮影後に画面左下へサムネイル表示。コピー / 保存 / 編集 / ドラッグ&ドロップ(FinderやSlackへ直接ドロップ可)
- **注釈エディタ** — 矢印・直線・四角・楕円・ペン・ハイライト・テキスト・モザイク、Undo/Redo(⌘Z / ⇧⌘Z)、注釈込みコピー(⇧⌘C)・保存(⌘S)
  - **選択/移動ツール** — 置いた注釈をクリックで選択し、ドラッグで自由に移動。描いた直後の図形はそのまま掴んで動かせる
  - テキストは**ダブルクリックで再編集**、選択中に Delete で削除、スウォッチで色変更。移動・削除・再編集も Undo 可能
- **設定** — 保存先フォルダ、自動コピー(デフォルトON)、自動保存、ログイン時起動

Retina 対応(2x PNG に正しい DPI を埋め込み)。撮影時に自アプリのパネルは写り込まない。

## ビルドと起動

Xcode 不要(Command Line Tools のみでOK)。

```bash
./build.sh && open Kiritori.app
```

## 初回セットアップ

1. 起動するとメニューバーにカメラアイコンが出る
2. 初回撮影時に「画面収録」の許可を求められる
   → システム設定 > プライバシーとセキュリティ > **画面収録とシステムオーディオ録音** で Kiritori を許可
3. **アプリを再起動**(メニューから終了 → `open Kiritori.app`)すると撮影できるようになる

※ ad-hoc 署名なので、再ビルドすると画面収録の許可が外れることがあります。その場合はシステム設定で一度オフ→オンにし直してください。

## 構成

| ファイル | 役割 |
|---|---|
| `Sources/Kiritori/AppMain.swift` | メニューバー・ホットキー・撮影フロー・権限 |
| `Sources/Kiritori/CaptureEngine.swift` | ScreenCaptureKit によるキャプチャ |
| `Sources/Kiritori/SelectionOverlay.swift` | 範囲/ウィンドウ選択オーバーレイ |
| `Sources/Kiritori/QuickActionPanel.swift` | 撮影後のフローティングパネル |
| `Sources/Kiritori/Editor.swift` | 注釈エディタ(図形・描画・書き出し) |
| `Sources/Kiritori/SettingsView.swift` | 設定画面 |
| `Sources/Kiritori/HotKeyManager.swift` | Carbon グローバルホットキー |

## 今後の拡張候補

- 画面録画(動画 / GIF)— `SCStream` + `AVAssetWriter`
- スクロールキャプチャ
- OCR(テキスト認識)— Vision framework の `VNRecognizeTextRequest`
- ピン留め(スクリーンショットを最前面に貼り付け)
- ホットキーのカスタマイズ
