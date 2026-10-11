# Suno 用 BGM プロンプト — Waddly 30 秒プロモ

ナレーションなし・BGM のみ。**30.00 秒**の映像に合わせて切る前提です。
Suno は数分のトラックを返すので、**2〜3 本生成して一番良い 30 秒を切り出す**のが現実的です。

---

## 1. まず決めておくこと

| 項目 | 値 | 理由 |
| --- | --- | --- |
| BPM | **96**（95〜100 可） | 打鍵のリズム（1 打 ≈ 0.12〜0.2 秒）とぶつからない。速いと急かされる |
| キー | **F メジャー**（または C メジャー） | 明るいが子供っぽすぎない。最後の「解決」が気持ちよく決まる |
| 長さ | 60〜90 秒を生成して 30 秒に切る | サビ前〜サビがちょうど 30 秒に収まる |
| ボーカル | **なし（Instrumental）** | 指定どおり |
| 音数 | 少なめ | 効果音（打鍵音・スパークル）を重ねるので、帯域を空けておく |

---

## 2. メインのプロンプト（Suno の「Style of Music」欄に貼る）

```text
Instrumental cozy electronic for a cute macOS desktop-pet app promo. Warm marimba and music-box lead, soft felt piano, rounded Rhodes chords, gentle analog pad, light shaker and finger snaps, soft kick with no snare, tiny chiptune blips as texture. 96 BPM, F major, clean and minimal arrangement, lots of space in the mid range, soft tape saturation, gentle low-pass warmth. Playful but calm, hopeful and inviting, slightly magical. No vocals, no lyrics, no heavy drums, no distortion, no orchestral swell.
```

### 短縮版（文字数制限が厳しいとき）

```text
Instrumental cozy electronic, cute macOS app promo, warm marimba & music box, felt piano, soft Rhodes, light shaker, soft kick, chiptune blips, 96 BPM, F major, minimal, warm tape, hopeful and magical, no vocals, no drums
```

### Exclude styles（除外指定がある場合）

```text
vocals, lyrics, singing, heavy drums, aggressive, distortion, EDM drop, dubstep, orchestral, cinematic trailer, lo-fi hiss, vinyl crackle
```

---

## 3. 歌詞／構成欄（Lyrics 欄）

インストゥルメンタル指定が使えるなら空のままで構いません。
構成を誘導したい場合は次を貼ってください（歌詞ではなくセクション指示として解釈されます）。

```text
[Instrumental]

[Intro: soft music box and airy pad, sparse, 4 bars]
[Build: marimba enters with a light shaker, gentle pulse, 4 bars]
[Main: warm Rhodes chords, playful marimba melody, soft kick, 8 bars]
[Bridge: strip back to felt piano and pad, spacious, 4 bars]
[Lift: melody returns brighter, snaps and blips, 8 bars]
[Outro: single marimba note rings out over the pad, resolve, 2 bars]
```

---

## 4. タイトル案

- `Waddly — Tiny Companion`
- `Desk Pet Days`
- `Waddle & Type`
- `Small Friend on Your Desktop`

---

## 5. 代替案（雰囲気を変えたいとき）

**A. チップチューン寄り（もっとゲームっぽく）**

```text
Instrumental chiptune-tinged lo-fi, cute macOS app promo, square-wave lead with soft edges, music box, warm pad, soft kick and shaker, 100 BPM, C major, playful and nostalgic, minimal, no vocals, no heavy drums
```

**B. ローファイ・ヒップホップ寄り（もっと落ち着く）**

```text
Instrumental lo-fi hip hop for a cozy desktop pet app, dusty Rhodes, soft boom-bap kick, brushed snare, warm upright bass, music box accents, 88 BPM, F major, relaxed and warm, subtle, no vocals, no vinyl crackle
```

**C. やわらかいオーケストラ寄り（もっと上品に）**

```text
Instrumental gentle chamber pop, celesta, pizzicato strings, felt piano, soft woodwinds, light shaker, 96 BPM, F major, tender and hopeful, small ensemble, lots of space, no vocals, no cinematic trailer drums
```

---

## 6. 30 秒への切り出し方

映像の山は **27.55 秒の Enter**、解決は **28.1〜30.0 秒のロゴ**です。BGM もそこに着地させてください。

| 映像の区間 | 使いたい BGM の部分 |
| --- | --- |
| 0.0 – 2.8（ペット登場） | 静かな導入。音数が少ないところ |
| 2.8 – 8.4（タイピング） | リズムが出てくるが主役は打鍵音。**中域を空けたところ** |
| 8.4 – 17.0（AI → 登録） | 一番「わくわく」する部分。メロディが動くところ |
| 17.0 – 20.3（サイズ／モード） | 軽く弾むところ |
| 20.3 – 25.3（ドラッグ → まどろみ） | ブリッジ。いったん静かになるところ |
| 25.3 – 27.55（打鍵 → Enter） | 持ち上げて、Enter で落とす |
| 28.1 – 30.0（ロゴ） | 解決。余韻を残して終わる |

**探し方のコツ:** 生成した 60〜90 秒の中から「静かな導入 → メロディが乗る → いったん引く → 明るく戻る → 締まる」という 30 秒を探してください。映像の切り替わり（8.4 / 20.3 / 27.55）に BGM のフレーズ頭が来ると、いっしょに動いて見えます。

---

## 7. ミックスの目安（次の工程で）

- BGM は **-18 〜 -20 LUFS**（映像全体の目標は -14 LUFS 前後）。効果音に負けない程度に小さく
- **打鍵音が主役**の区間（3.25–7.20 / 25.65–27.55）は BGM を **2〜3 dB 下げる**
- 27.55 の Enter 直前 0.5 秒は BGM を少し下げて（または一瞬切って）インパクトを立てる
- 28.1 のロゴで BGM を戻し、30.0 で自然に終わる（フェードアウトは 0.4 秒以内）
- 書き出しは **48 kHz / ステレオ / AAC 192〜256 kbps**

---

## 8. ライセンスについて

Suno で生成した音源の権利は **Suno の利用規約と契約プランに依存します**（無料プランは非商用限定、Pro/Premier は商用可など）。
公開前に <https://suno.com/terms> で当該プランの条項を確認してください。
本プロジェクトでは生成物をリポジトリに含めず、`audio/bgm/` に置くだけにしています（`.gitignore` 済み）。
