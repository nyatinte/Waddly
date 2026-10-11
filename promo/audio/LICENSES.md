# 音源のライセンス — Waddly プロモ

**公開前に必ず一次情報を確認してください。** ここに書いたのは 2026-10-10 時点の要約です。
各サイトは予告なく条件を変えることがあります。

---

## 1. Mixkit（今回ダウンロード済み・22 音）

- ライセンス: **Mixkit Sound Effects Free License**
- 一次情報: <https://mixkit.co/license/#sfxFree>
- 要約:
  - 商用・非商用を問わず、無料で利用できる
  - **クレジット表記は不要**
  - **音源そのものを再配布することはできない**（別のストックライブラリ、素材集アプリ、テンプレートとして配るなど）
  - 音源を主役にした商品（効果音アプリ等）には使えない
- 今回の使い方は「動画の効果音として使う」なので、**条件を満たしています**
- 注意: Mixkit は **音源ごとにライセンスが違います**。動画・音楽・テンプレート・アートは別ライセンスです。
  今回はすべて `Sound Effects` なので上記が適用されます。

### ダウンロードした音源

`audio/sfx/mixkit-manifest.json` に元 ID と名前を記録しています。
再取得は `audio/tools/fetch-mixkit-sfx.sh`（WAV はリポジトリに入れていません）。

---

## 2. Pixabay（今回は取得できず）

- ライセンス: **Pixabay Content License**
- 一次情報: <https://pixabay.com/service/license-summary/>
- 要約:
  - 商用・非商用を問わず無料
  - **クレジット表記は不要**（推奨はされている）
  - 素材そのものの再配布・転売はできない
  - 音楽は「動画・ポッドキャスト等に組み込んで使う」のは OK
- **今回は取得できませんでした**: Pixabay は非ブラウザのクライアントを Cloudflare で遮断しており（HTTP 403）、
  この作業環境のブラウザ自動化もサンドボックスの制約で起動できませんでした。
- このプロジェクトでは**未使用**です（音源は Mixkit で足りました）。

### おすすめの検索先（ブラウザで開く）

| 用途 | URL |
| --- | --- |
| 打鍵音 | <https://pixabay.com/sound-effects/search/keyboard%20typing/> |
| UI クリック | <https://pixabay.com/sound-effects/search/ui%20click/> |
| きらめき | <https://pixabay.com/sound-effects/search/sparkle/> |
| スウッシュ | <https://pixabay.com/sound-effects/search/whoosh/> |
| 着地 | <https://pixabay.com/sound-effects/search/thud/> |

---

## 3. Freesound（今回は取得できず）

- ライセンス: **音源ごとにバラバラ**（CC0 / CC-BY 3.0 / CC-BY 4.0 / CC-BY-NC / Sampling+ など）
- 一次情報: <https://freesound.org/help/faq/#licenses>
- 重要:
  - **CC0** … クレジット不要。商用可
  - **CC-BY** … **クレジット表記が必須**。商用可
  - **CC-BY-NC** … 商用不可。プロモには使えない
  - Freesound 全体に単一のライセンスはないので、**1 音ずつ確認が必要**
- **今回は取得できませんでした**: API キーが必要です（`https://freesound.org/apiv2/apply/` で取得、無料）。
- このプロジェクトでは**未使用**です（音源は Mixkit で足りました）。

### CC-BY の音源を使う場合の表記例

```text
"Keyboard typing" by user_name (https://freesound.org/s/12345/)
Licensed under Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/)
```

---

## 4. Suno（BGM・これから生成）

- 一次情報: <https://suno.com/terms>
- 生成物の権利はプランに依存します（無料プランは非商用限定、有料プランは商用可、など）。
- **公開前に必ずご自身のプランの条項を確認してください。**
- 本リポジトリには生成物を含めません（`audio/bgm/` は `.gitignore` 済み）。

---

## 5. この動画に含まれるその他の第三者素材

| 種類 | 使用 | ライセンス |
| --- | --- | --- |
| ペット画像・アプリアイコン | 作者本人の著作物 | MIT 対象外（[README](../../README.md) 参照） |
| 壁紙・メニューバー・Dock・キーボード・ポインタ・ロゴ | すべて本プロジェクトで描画 | Apple の素材は不使用 |
| Noto Sans JP | テキスト描画 | SIL OFL 1.1（[LICENSE-THIRD-PARTY.md](../LICENSE-THIRD-PARTY.md)） |
| GSAP 3 | レンダリング | GreenSock Standard License（同上） |

---

## 6. 公開時のチェックリスト

- [ ] 使った効果音がすべて Mixkit のもの → **表記不要**。`mixkit-manifest.json` を保管しておく
- [ ] Pixabay の音源を足した → **表記不要**だが、元 URL を控えておく
- [ ] Freesound の音源を足した → **CC0 以外ならクレジット表記を動画説明欄に入れる**
- [ ] BGM が Suno の有料プランで生成されたものか確認した
- [ ] `audio/sfx/` の WAV を**そのまま配布していない**（Mixkit の再配布禁止に触れるため）
