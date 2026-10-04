# ADR 0001: Swift製デスクトップペットの方針

- 状態: 実装中
- 更新日: 2026-10-04
- 実装: Waddly 0.1.0 を Release ビルド済み。公開準備中

## 背景

16 コマのペンギン画像を標準ペットにし、キー入力に反応する macOS 常駐アプリ Waddly を作る。自分の Mac で使える Release ビルドとディスクイメージを用意し、常駐メモリ 100MB 未満を目標にする。

## 決定

### 対象環境

- macOS 専用で、macOS 14 以降を対象にする。ビルド時に実行中の Mac の CPU アーキテクチャを選ぶ。
- 開発環境は macOS 27.0、Apple Swift 6.4、macOS SDK 27.0。Xcode 本体ではなく Command Line Tools を使う。
- `.app` と `.dmg` を生成する。Developer ID 証明書がないため、現状はバンドル ID を基準に ad-hoc 署名し、公証と App Store 対応は未実施。

### アプリと表示

- Dock とメニューバーに表示し、サイズ変更、一時停止、終了などをメニューから操作する。
- ペンギンは透明な最前面パネルに表示する。常にドラッグ可能で、表示範囲のクリックは背後のアプリに届かない。
- 通常のデスクトップ Spaces に表示し、フルスクリーンアプリ上には出さない。複数ディスプレイではドラッグ先を記憶する。
- 初回は画面右下に置き、ドラッグ後の位置を次回起動時にも使う。
- サイズはメニューから 180px、240px、320px の 3 段階で変更する案とし、標準サイズは 240px を仮置きする。
- ログイン時起動は設定で選べるようにする。初期値は無効とする。
- Apple 標準の AppKit、CoreGraphics、Core Animation を優先する。要件を満たす既存ライブラリや実装があれば、保守状況、権限、サイズ、ライセンスを確認してから採用する。

### 入力の扱い

- 実際の文字列やキーコードを取得・保存しない。キー入力イベントの回数と間隔だけをその場で使い、ログ、ネットワーク送信、テレメトリーは行わない。
- macOS の許可を得た読み取り専用の入力イベント監視を使う。実装時に `CGEventTap` の listen-only 方式を試し、必要な権限と再ビルド時の権限維持を実機で確認する。
- 権限がない場合もアプリを起動できるようにし、状態と設定画面への案内をメニューに出す。

### アニメーション

- 同梱済みの 16 コマ画像を使い、タイピング中はコマを切り替えて軽く弾ませる。
- 最後の入力から 2〜3 秒で通常待機、20〜30 秒で睡眠へ移る。
- 睡眠中は呼吸のような小さな動きを続ける。睡眠開始から 5 分後にアニメーションを止めて静止する。
- 長時間停止後も、キー入力で復帰できるよう入力イベントの検知は続ける。監視は引き続き内容を保存しない。

### 軽量性

- 目標は Release ビルドの常駐プロセスメモリ 100MB 未満。常時描画や不要なポーリングを避け、入力イベントの連続通知はまとめて UI へ反映する。
- 判定は実機の Release ビルドで行う。通常待機、タイピング中、睡眠静止中のメモリを測定する。
- 不要な外部ランタイムや重い描画フレームワークは追加しない。

## 初回検証

- Swift 6 モードで警告をエラーにして型チェック済み。
- Release ビルド、署名、Info.plist、状態遷移の自己テストに成功。
- Waddly 0.1.0 の待機アニメーション中、起動約 13 秒後は RSS 52,176 KB（約 51 MiB）、物理メモリフットプリント約 12 MB（ピーク約 13 MB）。
- 100MB の目標は両方の指標で下回る。入力中と長時間静止後は未計測。
- 入力監視許可はユーザー操作が必要。アプリ ID を変更したため、初回起動時に再許可が必要。

## 既存実装の調査

[TypingPetMac](https://github.com/ApthsN/TypingPetMac)は、Swift 製で MIT ライセンスの macOS デスクトップペット。最前面表示、ドラッグ、位置記憶、メニューバー操作、キー反応を備えている。

コードは取り込まず、UI やイベント監視の設計例としてのみ参照する。入力権限方式やライフサイクル上の注意点を調べ、Apple 標準 API で要件を満たす小さな実装を作る。外部ライブラリは具体的な利点が確認できた場合だけ追加する。

## 未決事項

- サイズ段階の値と不透明度。240px を標準サイズとして仮置き中。
- 実際に必要となる macOS の入力監視権限と署名方式
- タイピング中と睡眠静止中のメモリ計測

## 参考資料

- [Apple: CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [Apple: CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess())
- [Apple: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Typibara: Privacy Policy](https://www.typibara.com/privacy-policy)
- [TypingPetMac: Source and MIT License](https://github.com/ApthsN/TypingPetMac)
