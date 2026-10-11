# 2体目のペット — 画像生成プロンプト（3×3 スプライトシート）

プロモの「Before → After」で使う2体目（猫）の素材を作るためのプロンプト。
既存の `nyatinte-bot`（黒ペンギン＋青ニット帽＋ノートPC）と**同じ仕様・同じ画風**で
出力すれば、そのまま差し替えできます。

---

## 1. 出力仕様（これを満たさない画像はスライスできない）

| 項目 | 値 |
| --- | --- |
| 形式 | PNG / 正方形 1:1 |
| 解像度 | **1024×1024**（最低 768×768、3の倍数の正方形） |
| レイアウト | 3列 × 3行、9コマ、行優先（左上→右→下） |
| 背景 | 単色ベタ（純白 `#FFFFFF` か マゼンタ `#FF00FF`）※透過は後処理で抜く |
| 画風 | ドット絵／低解像度ピクセルアート（論理解像度 48〜64px 程度を等倍拡大） |
| 輪郭 | 黒の太いアウトライン、**アンチエイリアスなし・ぼかしなし・グラデなし** |
| 余白 | 各セル内で上下左右 8% 程度の空き。**セル境界をまたがない** |
| 一貫性 | 9コマすべて同一キャラ・同一比率・同一カメラアングル・同一足元ベースライン |

### 9コマの内訳（この順番が固定）

| # | 位置 | ファイル名 | 内容 |
| --- | --- | --- | --- |
| 1 | 1行1列 | `idle-1` | 立ち、目を開けて正面 |
| 2 | 1行2列 | `idle-2` | 立ち、目を閉じてにっこり（まばたき） |
| 3 | 1行3列 | `typing-1` | ノートPCの後ろでタイピング、目を開けて画面を見る |
| 4 | 2行1列 | `typing-2` | タイピング、少し上に弾む |
| 5 | 2行2列 | `typing-3` | タイピング、ウインク、青い効果線（小） |
| 6 | 2行3列 | `typing-4` | タイピング、目を細め前のめり、青い効果線（大） |
| 7 | 3行1列 | `enter-1` | 青いEnterキーを勢いよく叩く、頭が下がる、黄色いキラキラ＋効果線 |
| 8 | 3行2列 | `sleep-1` | うとうと、目を閉じる、白い「Z」が1つ |
| 9 | 3行3列 | `sleep-2` | 完全に寝ている、頭を伏せる、「Z」が2つ |

### ブランド固定色（この色は必ず入れる）

| 用途 | 色 |
| --- | --- |
| ニット帽（メイン） | `#2792F5` |
| ニット帽（影） | `#106CD0` / `#064DA5` |
| 体（黒） | `#050506` |
| 顔・おなか（クリーム） | `#FCF8ED` |
| ほっぺ（ピンク） | `#FBC5AF` |
| 手足・くちばし（アンバー） | `#F1AD1E` |
| ノートPC（ダークグレー） | `#2F434F` |
| 効果線（水色） | `#17C7E1` |
| キラキラ（黄） | `#F1AD1E` / `#FFD75E` |

> 帽子のブルーとEnterの黄色はプロモ全体のアクセントなので、
> 2体目でも**青いニット帽とノートPCはそのまま引き継ぐ**（種族だけ変える）。

---

## 2. メインプロンプト（英語・そのまま貼る）

```
Pixel-art sprite sheet of ONE single character, 3x3 grid, 9 frames, chunky
low-resolution pixel art (roughly 48x48 logical pixels upscaled with hard square
pixels), flat solid colors, thick black outlines, crisp axis-aligned pixel steps,
no anti-aliasing, no blur, no gradients, no dithering.

Character: a chubby round ginger tabby cat mascot with a huge head and a tiny
body, big glossy black eyes with a single white highlight, rosy pink cheeks,
small amber-yellow paws and belly. It wears a royal-blue knitted beanie with a
pompom and a ribbed brim (blue #2792F5, shading #106CD0) and sits behind a small
dark-grey laptop (#2F434F) with a light grey screen and a tiny sticker on the
lid. Cute chibi kawaii sticker style, three-quarter front view facing the camera,
identical proportions and identical camera angle in every frame. The character's
feet stay on the same baseline in every frame.

Layout is row-major, 3 columns by 3 rows, in exactly this order:
row 1: standing idle with eyes open, no laptop / standing idle with eyes closed
in a happy blink, no laptop / sitting behind the laptop typing with eyes open
looking at the screen;
row 2: typing with eyes open and body bobbing up / typing with one eye winking
and small cyan motion marks on both sides / typing with both eyes squinting,
leaning forward, stronger cyan motion marks;
row 3: slamming a big blue keycap that has a white return-arrow glyph, head down,
yellow sparkles and cyan motion marks around it / dozing off with eyes closed and
one small white "Z" floating up / fast asleep with head resting down and two "Z"s
floating up.

Each character is centered inside its own cell with about 8% empty margin on all
sides; nothing crosses a cell boundary. No grid lines, no cell borders, no
frames, no drop shadows, no floor, no background scenery, no watermark, no
signature. Plain flat pure-white background.
```

### ネガティブプロンプト

```
anti-aliasing, soft edges, blurry, gradient shading, dithering, 3D render,
smooth vector art, photorealistic, painted, watercolor, extra limbs, extra eyes,
extra ears, duplicated character, different characters in different cells,
inconsistent size, inconsistent pose scale, cropped ears, cropped pompom,
overlapping cells, bleeding across cells, grid lines, cell borders, drop shadows,
background scenery, floor, horizon, watermark, signature, logo, caption,
multiple hats, missing hat, thin outlines, pastel wash, low contrast
```

> 注意: `text` / `letters` をネガティブに入れないこと。`Z` と `⏎` は
> デザインの一部として必要です。

### 日本語で投げる場合（Gemini / nano-banana など）

```
1枚のキャラクターのドット絵スプライトシート。3×3の9コマ。低解像度のピクセルアートを
等倍で拡大したような、硬い正方形ピクセル・ベタ塗り・太い黒輪郭。アンチエイリアス、
ぼかし、グラデーション、ディザは禁止。

キャラクター：ずんぐりした丸い茶トラ猫のマスコット。大きな頭と小さな体、つやのある
大きな黒い目（白いハイライト1点）、ピンクのほっぺ、アンバー色の小さな手足とおなか。
青いニット帽（ポンポンと折り返し付き、#2792F5 / 影 #106CD0）をかぶり、ダークグレーの
小さなノートPC（#2F434F、薄グレーの画面、ふたに小さなステッカー）の後ろに座る。
ちびキャラ・かわいい・ステッカー風。斜め前から見た向きで、9コマすべて同じ比率・同じ
アングル・同じ足元のベースライン。

並びは行優先で、1行目：立ち・目開き（PCなし）／立ち・目閉じ笑顔（PCなし）／PCの後ろで
タイピング・目開き／2行目：タイピング・体が少し弾む／タイピング・ウインク＋水色の効果線
（小）／タイピング・目を細め前のめり＋効果線（大）／3行目：青いEnterキーを叩く・頭が下がる
・黄色いキラキラと水色の効果線／うとうと・目閉じ・白い「Z」1つ／完全に就寝・頭を伏せ
「Z」2つ。

各コマは上下左右に8%程度の余白を残して中央に配置し、セルの境界をまたがないこと。
グリッド線、枠線、影、床、背景の装飾、ウォーターマーク、署名はなし。背景は純白ベタ。
```

---

## 3. バリエーション（キャラクター行だけ差し替える）

| 案 | 差し替える語句 | メモ |
| --- | --- | --- |
| **茶トラ猫（推奨）** | `a chubby round ginger tabby cat mascot` | 黒ペンギン→茶トラで Before/After が一目で伝わる |
| 柴犬 | `a chubby round shiba inu puppy mascot with a cream belly and pointed ears` | 耳が帽子と干渉しやすいので注意 |
| 黒猫 | `a chubby round black cat mascot with a cream belly` | 1体目と同系色で変化が弱い |
| ハムスター | `a chubby round golden hamster mascot with a cream belly and tiny round ears` | 耳が小さいので帽子と相性が良い |

---

## 4. 生成後の処理

```bash
# 1) 受け取った画像を所定の名前で置く（<name> は任意の識別子）
cp ~/Downloads/cat-3x3.png promo/assets/pets/cat-3x3.png

# 2) 256px セルに 1:1 でスライス（Nearest / アンチエイリアスなし）
#    assets/pets/*-3x3.png を自動検出し、scripts/pets.js も再生成される
promo/tools/build-pets.sh
```

- `build-pets.sh` が `assets/frames/<name>/` に9コマを書き出し、
  `scripts/pets.js` の `window.PET_SETS` を更新します。
- セル境界の滲み（浮いた点）は `tools/despeckle.py` が自動で除去します（Issue #53）。
- スライス後、`assets/frames/<name>/idle-1.png` を目視確認してください。

---

## 5. 受け入れチェック

- [ ] 1024×1024 の正方形、3の倍数で割り切れる
- [ ] 9コマすべて同じキャラ・同じ比率・同じアングル
- [ ] 足元のベースラインが全コマで揃っている
- [ ] セルの境界をまたいだ描き込みがない（滲み・浮いた点）
- [ ] 青いニット帽（`#2792F5` 系）とノートPCが入っている
- [ ] Enterコマに黄色のアクセントがある
- [ ] 背景が単色ベタで、キャラの輪郭が潰れていない
- [ ] 拡大しても輪郭がぼけていない（硬いピクセル）
