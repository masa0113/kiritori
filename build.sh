#!/bin/zsh
# Kiritori.app をビルドして .app バンドルを組み立てる
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Kiritori.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kiritori "$APP/Contents/MacOS/Kiritori"
cp Info.plist "$APP/Contents/Info.plist"

# ad-hoc 署名(TCC の許可をバンドルに紐付けるため)
codesign --force --sign - "$APP"

echo "✅ ビルド完了: $(pwd)/$APP"
echo "   open $APP で起動できます"
