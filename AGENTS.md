# Agent instructions

## 日本語

### 開発環境とコードの配置

既存のSwift 6、AppKit、macOS 13以降の構成で変更してください。システムAPIを優先し、新しい依存関係の追加は避けてください。

画像モデル、画像の読み込み、画像処理は`Sources/WaddlyCore`に配置してください。アプリのライフサイクル、入力監視、UIは`Sources/WaddlyApp`に配置してください。

### プライバシー

キーコードは入力イベントの処理中に、Enterキーかどうかを判定するためだけに使ってください。キーコードを保存、ログ出力、送信してはいけません。読み込んだ画像は端末内に保持してください。

### 翻訳とドキュメント

ユーザー向けの文字列を追加・変更するときは、`macos/ja.lproj/Localizable.strings`と`macos/en.lproj/Localizable.strings`の両方を更新してください。

ユーザーから見える動作やセットアップ手順を変更したら、`README.md`と`README.en.md`の両方を更新してください。

### 検証

Swiftのコードを変更したら、`swift test`でテストを実行し、`./macos/build.sh`でビルドしてください。ビルドスクリプトはSwiftLintの厳格な検査を実行し、Release版のアプリを作成します。

## English

### Development environment and code placement

Keep changes within the existing Swift 6, AppKit, and macOS 13+ setup. Prefer system APIs and avoid adding dependencies.

Keep image models, image import, and image processing in `Sources/WaddlyCore`. Keep the app lifecycle, input monitoring, and UI in `Sources/WaddlyApp`.

### Privacy

Use key codes only while handling input events to identify Enter. Never store, log, or transmit key codes. Keep imported images on the device.

### Localization and documentation

When adding or changing user-facing strings, update both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.

When user-visible behavior or setup instructions change, update both `README.md` and `README.en.md`.

### Verification

After changing Swift code, run the test suite with `swift test` and build with `./macos/build.sh`. The build script runs strict SwiftLint checks and creates the Release app.
