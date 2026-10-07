[リリース前検証レポート](https://github.com/nyatinte/Waddly/blob/release/e2e-final-gate/docs/release-e2e-2026-10-05.md)

## Why the change

リリース前の実アプリ検証で見つかった画像登録・スクロール・Dock 再オープンの不具合 4 件を修正し、回帰テストと検証結果を残します。

## Special things to note

- [x] User-visible UI change — セットアップの表示領域を拡大し、Dock から設定を開き直せるようにします（比較画像は下記）。
- リリース判定は保留です。大画像の物理メモリは目標の 100 MB を超え、厳密な割り当て診断も約 3.23 KB の増加で失敗しています。この PR ではメモリ処理を変更しません。
- macOS 14、入力監視の許可変更、ログイン起動などは未検証です。公証なしの配布仕様・バージョンは変更せず、公開済み `0.1.2` の差し替えも行いません。

## Change outline

画像操作と再オープンの処理を、既存の AppKit の経路に戻します。

```diff
 セットアップの画像ページ
-  内側のカードもドロップを受信 → 登録処理なし
+  外側のページだけがドロップを受信 → 既存の画像登録処理
-  ページの高さ 300 / ウィンドウの高さ 440
+  ページの高さ 340 / ウィンドウの高さ 480

 アニメーション設定の画像行
-  hitTest が子ビューを親に置換 → スクロール操作を遮る
+  標準の hitTest → 子のスクロールビュー・ボタンへ入力

 Dock から再オープン
-  設定を開き直す処理なし
+  画像未登録 または セットアップ表示中 → セットアップを表示
+  それ以外 → アニメーション設定を表示
```

翻訳リソースをテストへ渡せるようにし、保存・異常系・画面操作の回帰テストを 10 件追加しました。

```text
LocalizationController(settings, resources: Bundle = .main)
  └─ 実際の日本語・英語の翻訳文でレイアウトを検証
Tests/WaddlyAppTests/
  ├─ SetupWizardTests.swift       # ドロップ・レイアウト・スクロール・画面遷移
  └─ AppIntegrationTests.swift    # 保存・編集・異常系・メニュー・再オープン
README.md / README.en.md          # 変更した操作を説明
docs/release-e2e-2026-10-05.md     # 実機結果・メモリ測定・未検証項目
Tools/profile_image_app.swift    # RSS とピーク RSS も記録（処理は変更なし）
```

`mise run check` は 38 テストと Release ビルドを含め通過しました。DMG 作成・署名検証と既定の `mise run memory:test` も通過しました。実機では画像編集、言語切替、再起動後の保存、利用者によるドラッグとキー入力を確認しています。

同条件の大画像プローブで `d810c9e` → `429f932` を交互に 3 回ずつ実測しました（MB は 1,000,000 バイト、値は各版の中央値）。メモリ削減は見られず、小幅な増加の原因は未確定です。前後とも 100 MB 目標を超えています。各回の値と再現手順は検証レポートに記録しています。

| 指標 | PR 前 | PR 後 | 差（後 − 前） |
| --- | ---: | ---: | ---: |
| ピーク物理メモリ | 133.84 MB | 134.14 MB | +0.29 MB |
| 設定表示 30 秒後 | 103.47 MB | 103.88 MB | +0.41 MB |
| 設定を閉じた 30 秒後 | 103.61 MB | 104.07 MB | +0.46 MB |
| ピーク RSS | 283.41 MB | 283.64 MB | +0.23 MB |

状態メッセージの修正前・修正後。

| 修正前 | 修正後 |
| --- | --- |
| ![状態メッセージが切れている画像ページ](https://raw.githubusercontent.com/nyatinte/Waddly/4c33b50c3a89d7eec688e3415de7aea0271d52a4/docs/images/release-e2e-setup-before.png) | ![状態メッセージが表示される画像ページ](https://raw.githubusercontent.com/nyatinte/Waddly/4c33b50c3a89d7eec688e3415de7aea0271d52a4/docs/images/release-e2e-setup-after.png) |
