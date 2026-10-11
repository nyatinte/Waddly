# Waddly プロモーション映像

Waddly のプロモーション映像（30 秒）です。**macOS のみ / ナレーションなし**。
画面上のものはすべてコードで描いており、Apple の壁紙・アイコン・商標は使っていません。

**日本語版と英語版**があります。**絵はまったく同じ**で、違うのは文字だけです。

| 完成品 | 画面の文字 |
| --- | --- |
| [`out/waddly-promo-ja-1920x1080-60fps.mp4`](out/waddly-promo-ja-1920x1080-60fps.mp4) | 日本語キャプション 5 枚 ＋ 機能ラベル ＋ ロゴ（既定） |
| [`out/waddly-promo-en-1920x1080-60fps.mp4`](out/waddly-promo-en-1920x1080-60fps.mp4) | 同じ位置に短い英語（全 21 語） |

| | |
| --- | --- |
| 仕様 | 1920×1080 / 60 fps / 1800 フレーム / H.264 + AAC / **30.00 秒** |
| 容量 | 日本語版 21.9 MB / 英語版 22.0 MB |
| 音 | BGM + 効果音（**-14.0 LUFS** / True Peak -1.3 dBFS）。**両言語で同じマスター** |
| 絵コンテ | [`docs/storyboard-ja.jpg`](docs/storyboard-ja.jpg) / [`docs/storyboard-en.jpg`](docs/storyboard-en.jpg) |
| 言語の比較 | [`docs/langs-comparison.jpg`](docs/langs-comparison.jpg) |
| 素材の権利 | [`LICENSE-THIRD-PARTY.md`](LICENSE-THIRD-PARTY.md) |

---

## 言語の切り替え

**映像のコードは 1 つだけ**です。文字は [`scripts/locales/`](scripts/locales/) にあり、
`window.LOCALES[lang]` を読むだけ。タイミングは `scripts/story.js` のビート表が持ち、
ロケールは**文章だけ**を持つので、翻訳が絵とズレることが原理的に起きません。

```
scripts/
  story.js            30 秒の演出（カメラ・シーン・タイミング）。言語を知らない
  locales/ja.js       日本語の文字だけ
  locales/en.js       英語の文字だけ
```

キャプションは**時間（story.js）と文章（locales/*.js）を別々に持ち、順番で対応**させます。

```js
// scripts/story.js
const CAPTION_AT = [[1.45, 2.80], [3.55, 6.95], [15.15, 17.10], [18.35, 21.90], [24.95, 26.30]];
```
```js
// scripts/locales/ja.js
captions: ["デスクトップに、ちいさな相棒。", "キーを打つたび、動き出す。", ...],
```

言語は `index.html` の `data-composition-variables` で宣言した `lang` ひとつで選びます。

```sh
./tools/render-langs.sh          # ja と en を両方
./tools/render-langs.sh en       # 片方だけ
./tools/snapshot.sh ja --at 4.60,16.45,18.90 -o snapshots/ja
```

`hyperframes render` は `--variables '{"lang":"en"}'` を受け取れますが、
`snapshot` は受け取れないので、どちらも [`tools/with-lang.sh`](tools/with-lang.sh) を通します
（`index.html` の既定値を一時的に書き換え、失敗しても必ず元に戻します）。

---

## 構成

ハードカットをせず、**1 つのデスクトップをカメラが移動する**構成です。

| 時間 | 内容 |
| --- | --- |
| 0.0 – 2.8 | 登場。Dock の Waddly アイコンが光り、ペンギンが跳ねてデスクトップへ |
| 2.8 – 8.4 | タイピング。手前のフルキーボードがせり上がり、キーが光り、ペンギンが打つ |
| 8.4 – 17.0 | **自分の画像**。3×3 シートが生成される → アプリへドラッグ → 9 コマが **3×3 に並ぶ** |
| 16.45 – 17.65 | **変身**。猫（16.45）→ ひよこ（17.05）→ **ペンギン（17.65）で定着** |
| 17.6 – 22.5 | **ステータス紹介**。小 / 中 / 大（18.0）→ 通常 / タイピング / スリープ（20.4） |
| 22.5 – 26.2 | 自由な配置。カーソルでつかんでドラッグ、着地、まどろみ |
| 26.2 – 30.0 | Return。打鍵 → 押し込み → 反応 → ロゴと GitHub リンク |

**主役はペンギン**です。登録したキャラクターは試着して、すぐペンギンに戻ります。
**最後もペンギンで終わります**。

### 変身（16.45 – 17.65 秒）

登録したシートを**その場で試着**します。**画面下部に 3 体のピッカーを出し、
選択リングが 猫 → ひよこ → ペンギン と移って、ペンギンで止まります**。
「他にも登録できる」と「最後に残るのはどれか」を、文字なしで同時に伝えるための仕掛けです。

- 切り替えのたびに白い閃光・拡大のポップ・きらめく粒子・低音の衝撃を重ねる
- コマの切り替えは**必ずハードスワップ**。カメラ・背景・テロップだけが滑らかに動く

### ポインタの扱い

ポインタが出るのは**ポインタが本来ある場所だけ**です。

- シートをアプリへ運ぶ（12.2 – 13.4）
- ペットをつかんで動かす（22.6 – 25.4）

タイピングと最後の Return は**マウスで操作しません**（キーボード HUD と、自分で沈む Return キー）。

---

## 画面の文字（全量）

| | 日本語版 | 英語版 |
| --- | --- | --- |
| キャプション 1 | デスクトップに、ちいさな相棒。 | A tiny pet for your desktop. |
| キャプション 2 | キーを打つたび、動き出す。 | Type, and it moves. |
| キャプション 3 | 好きな画像を、ペットに。 | Make your own pet. |
| キャプション 4 | 大きさも、動きも、選べる。 | Pick a size. Pick a mood. |
| キャプション 5 | ドラッグで、好きな場所へ。 | Drag it anywhere. |
| ドロップ領域 | 3×3 PNG をここにドロップ | Drop a 3×3 PNG |
| 締めのコピー | キーを打つたび、そばにいる。 | Always there while you type. |
| 動作要件 | macOS 14 以降 · Apple Silicon | macOS 14+ · Apple Silicon |
| メニューバー | ファイル | File |
| 共通 | `Waddly` / `return`（キーの印字）/ `github.com/nyatinte/Waddly` / キーボードの英字 | 同左 |

`小 / 中 / 大` と `通常 / タイピング / スリープ` は**文字を使わず**、
**物差しブラケットと育つ点**、**呼吸・キーボード・Zzz のピクトグラム**で示します。両言語で同じ絵です。

---

## 演出の仕掛け（言語に依存しない部分）

| 仕掛け | 何を伝えるか | どこで |
| --- | --- | --- |
| **章のピクトグラム**（右上） | いま何の話か | 全編。毎回同じ位置 |
| **因果のワイヤ** | 打鍵ごとに光の粒がキーボードからペットへ走る | 3.3 – 7.4 秒 |
| **依頼バブルの絵** | この画像を 3×3 のシートにして（写真 → 矢印 → 3×3） | 8.6 – 17.0 秒 |
| **セットアップ窓の絵** | 3 ステップ中 2 番目。ここに 3×3 を落とす | 11.4 – 17.0 秒 |
| **物差しブラケット ＋ 育つ点** | 小・中・大 | 18.0 – 19.8 秒 |
| **モードのピクトグラム** | 通常（呼吸）・タイピング・スリープ（Zzz） | 20.4 – 21.9 秒 |
| **3 体のピッカー** | 他のキャラも登録できる。最後に残るのはどれか | 16.2 – 17.9 秒 |
| **Dock のリング ＋ 4 回のホップ** | このアプリが出どころ。生きている | 0.7 – 2.4 秒 |
| **言葉なしのタグライン** | キーボード → 跳ねるペット | 27.7 – 30.0 秒 |

---

## キャラクター（自分で作れる）

| キャラクター | 出典 | 用途 |
| --- | --- | --- |
| `nyatinte-bot`（ペンギン） | アプリ同梱 | **主役**。全編を通して登場 |
| `cat`（猫） | ユーザーが登録するシート | 変身 1 体目 |
| `chick`（ひよこ） | ユーザーが登録するシート | 変身 2 体目 |

3 体とも 3×3 のスプライトシートから 9 コマに分割しています。
コマの並びは固定で、`idle-1, idle-2, typing-1..4, enter-1, sleep-1, sleep-2`（行優先）。

### ピクセル等倍

`tools/build-pets.sh` は `-filter point` / `SCALE=1` で**元のセルサイズのまま**切り出し、
CSS 側は `image-rendering: pixelated` を指定しています。拡大しても輪郭がぼけません。

---

## 音（BGM と効果音）

### BGM

`Magical Motif`（Suno 生成）の **92.4587 秒から 30 秒**を使っています。
区間は耳ではなく [`audio/tools/analyse-bgm.py`](audio/tools/analyse-bgm.py) が選びます
（オンセット包絡からテンポ 98.25 BPM を検出 → 映像のアクセントが拍に乗る区間を採点 →
Return の 27.55 秒がちょうど拍になるよう位相を合わせる）。

### 効果音

Mixkit の音源を **-3 dBFS / 48 kHz** に正規化したものを `audio/sfx-norm/` に置いています。

**打鍵は 1 打 = 2 層**です。ラップトップのキーは「thock（胴鳴り）＋クリック」なので、
`key-hard`（-3 dB）と `key-single`（-5 dB）を重ね、さらに実録の打鍵ベッドを -23 dB で敷いて
1 台のキーボードとして聴かせます。打鍵 34 打・アクセント 51 点。

### ミックスの組み方

```sh
cd promo/audio
./tools/build-mix.sh 30          # BGM 切り出し → 効果音配置 → -14 LUFS に整音
python3 tools/verify-mix.py ja   # 納品ファイルから音をデコードして検算
```

`build-mix.sh` は**打鍵の時刻を `scripts/story.js` から直接読み出します**。
演出を直してもクリックが絵からずれません。

---

## ペットの動きはアプリの実装から移植

`Sources/WaddlyApp/PetAnimationController.swift` と `AppModels.swift` の定数をそのまま使っています。

| 挙動 | 値 |
| --- | --- |
| タイピングのコマ送り | 75 ms 間隔 |
| タイピングの弾み | 0.14 秒、`[0, amplitude, 0]` / keyTimes `[0, 0.45, 1]` |
| 待機の呼吸 | 1.01 倍 / 3.2 秒（自動反転） |
| まばたき | 0.16 秒 |
| 睡眠の呼吸 | 1.018 倍 / 1.5 秒、コマ送り 1.5 秒 |
| Enter の衝撃 | 0.58 秒、scale `[1, 0.86, 1.12, 0.96, 1]` / y `[0, 8, -5, 2, 0]` |
| 表示サイズ | 320 px（アプリの「大」） |
| 動きの強さ | strong（振幅 10） |

---

## 再レンダリング

```sh
cd promo
./tools/fetch-font.sh          # 初回のみ（OFL フォントを取得）
./tools/build-pets.sh          # スプライトシートを 9 コマに分割

./tools/render-langs.sh        # 日本語版と英語版（音の多重化まで一括）

./audio/tools/build-mix.sh 30  # 音を作り直す場合
./tools/snapshot.sh ja --at 4.60,16.45,18.90,27.60 -o snapshots/ja
```

`hyperframes` は HTML をヘッドレス Chrome で 1 フレームずつ描画して ffmpeg で結合します。
**すべての見た目が時刻 `t` の純関数**として書かれているため（`Date.now()` も `Math.random()` も未使用）、
どのフレームも毎回同じに描かれます。実際、日本語版・英語版は**同じ 1 本のタイムライン**を
文字だけ差し替えて 2 回描いたもので、尺は 1 フレームも違いません。

所要時間の目安: 1 言語あたり約 1 分 40 秒（Apple M5）。

---

## ファイル構成

```
promo/
  index.html              ルートコンポジション（lang の宣言だけ。演出は scripts 側）
  styles/main.css         デザインシステム + 演出の部品（壁紙・Dock・キーボード・Return キー・
                          ピクトグラム・因果のワイヤ・物差し・3 体ピッカー・ロゴ）
  scripts/engine.js       決定的なモーションエンジン + アプリから移植したペットの演技
  scripts/desktop.js      コードで描くデスクトップ（壁紙・メニューバー・Dock・ポインタ・アイコン）
  scripts/graphics.js     ピクトグラム一式（SVG 文字列を作るだけの純関数）
  scripts/story.js        30 秒の演出。言語を一切知らない
  scripts/locales/ja.js   日本語の文字だけ
  scripts/locales/en.js   英語の文字だけ
  scripts/pets.js         利用可能なキャラクター一覧（build-pets.sh の生成物）
  scripts/boot.js         一時停止した GSAP タイムラインの登録
  assets/pets/*-3x3.png   入力スプライトシート（nyatinte-bot / cat / chick）
  assets/frames/<name>/   分割済みの 9 コマ（生成物）
  assets/PROMPT-second-pet.md  追加キャラクター用プロンプト
  assets/brand/           アプリアイコン
  tools/build-pets.sh     シート分割 + ゴミ画素の除去
  tools/despeckle.py      孤立した微小な不透明領域だけを消す
  tools/fetch-font.sh     Noto Sans JP の取得
  tools/with-lang.sh      lang を一時的に切り替えてコマンドを実行し、必ず元に戻す
  tools/render-langs.sh   両言語のレンダリング + 多重化
  tools/snapshot.sh       言語を指定して任意フレームを書き出す
  audio/
    CUE-SHEET.md          効果音キュー
    SUNO-PROMPT.md        BGM 生成プロンプト
    LICENSES.md           音源ライセンスの確認結果
    mix-30s.wav           完成したミックス（両言語共通）
    sfx/ sfx-norm/ bgm/   生音源・正規化済み・BGM（いずれも git 管理外）
```

---

## 実装スタックについて（正直な評価）

**HyperFrames は無理をしていません。ただし、使っているのはごく一部です。**

実際に使っているのは次の 3 つだけです。

| 使っている | 中身 |
| --- | --- |
| `hyperframes render` | ヘッドレス Chrome でページを開き、`window.__timelines[id]` を 1 フレームずつ seek して撮影し、ffmpeg で結合 |
| `hyperframes snapshot` | 同じ仕組みで任意の時刻だけ書き出す |
| `hyperframes lint` | 静的検査 |

**使っていない**ものの方が多いです。`data-start` / `data-duration` による要素ごとのタイムライン、
`data-track-index`、`class="clip"`、サブコンポジション、ブロック／コンポーネント、レジストリ、
TTS、Studio のタイムライン。この映像は「1 つの連続したカメラ移動」なので、
要素ごとのシーン管理ではなく **`render(t)` という 1 つの純関数**で書く方が自然で、そうしています。

### 実際に困ったこと

1. **ルート HTML は 1 つだけ**（`multiple_root_compositions`）。複数カットは変数で切り替えるしかない
2. **`data-duration` は静的に読まれる**。尺の違うカットを作るときは、レンダリング前に
   `index.html` を書き換える必要があった（24 秒版を作ったときに実際に必要になり、
   [`tools/with-lang.sh`](tools/with-lang.sh) のようなラッパーを噛ませた）
3. **`snapshot` に `--variables` がない**。プレビューでも同じラッパーが要る
4. **lint の誤検知が 2 件**残る（`missing_timeline_registry` と
   `invalid_parent_traversal_in_asset_path`）。どちらも実際には問題なく描画できています

3 と 4 は今も残っていますが、**2 は今回の整理で消えました**
（日本語版と英語版は同じ 30 秒なので、尺を触る必要がない）。

### 他のスタックと比べた結論

- **Remotion**（[remocn.dev](https://remocn.dev/docs/getting-started/introduction)）は
  コンポジション・尺・props が一級市民なので、上記 1〜3 は最初から存在しません。
  React/TS の道具立てとホットリロードも魅力です。
  ただし (a) この映像の見た目は DOM + CSS で書かれており、React への移植は約 1,500 行の書き直し、
  (b) Remotion は**個人と 3 人以下の会社は無料、それ以上は有償ライセンス**です。
  今の品質を保ったまま移す価値があるかは、複数尺・複数比率を日常的に作るようになってから判断したいところです。
- **HyperFrames をやめて薄い自前レンダラにする**（Puppeteer + ffmpeg で 150 行程度）ことも可能です。
  この映像はすでに `render(t)` の純関数なので、必要なのは「seek して撮る」だけ。
  フレームワークの制約が全部消える代わりに、自前のインフラを保守することになります。

**今の結論: HyperFrames のままいく。** 理由は、実際の負担が「ラッパー 1 枚」と「lint の誤検知 2 件」だけで、
その代わりに**フレーム単位で完全に再現可能なレンダリング**が手に入っているからです
（同じソースから 2 回描くと SHA-256 が一致することを確認済み）。
尺や比率が増えて 2 の制約がまた効き始めたら、Remotion か自前レンダラに移るのが良いと思います。

---

## 生成した素材で見つかった不具合

`assets/pets/nyatinte-bot-3x3.png` には、コマ境界をまたいだ画素が混入していました。

- 3 行目中央（睡眠 A）の左端に、隣のコマ由来のオレンジ色の破片（93 px、4×24）
- 3 行目右（睡眠 B）と 2 行目右（タイピング C）に 1〜2 px の孤立点

アプリでも睡眠中のペットの横に小さな破片として見えます。プロモでは `tools/despeckle.py` で除去しています
（判定は**コマ面積に対する比率**で行うため、256 px のペンギンでも 418 px の猫でも同じ基準になります）。
**元のスプライトシート側も修正することをおすすめします**（Issue #53）。

## ライセンス

- コード（このディレクトリ）: リポジトリと同じ [MIT License](../LICENSE)
- ペット画像・アプリアイコン: 作者の著作物。MIT の対象外（[README](../README.md) 参照）
- BGM: Suno の生成物（作者提供）。効果音: Mixkit（[`audio/LICENSES.md`](audio/LICENSES.md)）
- 壁紙・メニューバー・Dock・アイコン・ポインタ: すべてこのプロジェクトで描画。Apple の素材は不使用
- 第三者ソフトウェア: [`LICENSE-THIRD-PARTY.md`](LICENSE-THIRD-PARTY.md)
