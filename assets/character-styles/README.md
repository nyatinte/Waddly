# Character style samples

Six reference sprite sheets, one per art style, used by Waddly's style chooser. Each sheet is a 3×3 grid of the nine poses required by the shared contract in [`prompts/en.md`](../../prompts/en.md), rendered with the style block for that style.

## Files

| File | Style | Look | Style prompt |
| --- | --- | --- | --- |
| [`pixel-art.png`](pixel-art.png) | Pixel Art | 16-bit-era pixel art with a small palette and hard edges. | [EN](../../prompts/pixel-art-en.md) / [JA](../../prompts/pixel-art-ja.md) |
| [`hand-drawn.png`](hand-drawn.png) | Hand-Drawn | Organic, slightly wobbly lines with flat colors and a sticker-like finish. | [EN](../../prompts/hand-drawn-en.md) / [JA](../../prompts/hand-drawn-ja.md) |
| [`iconic.png`](iconic.png) | Iconic | Bold, simplified silhouette with uniform line width and flat fills. | [EN](../../prompts/iconic-en.md) / [JA](../../prompts/iconic-ja.md) |
| [`retro-cartoon.png`](retro-cartoon.png) | Retro Cartoon | Thick ink lines, rounded features, pie-cut eyes, and a muted vintage palette. | [EN](../../prompts/retro-cartoon-en.md) / [JA](../../prompts/retro-cartoon-ja.md) |
| [`anime.png`](anime.png) | Anime | Cel shading with clean tapered lines and layered eye highlights. | [EN](../../prompts/anime-en.md) / [JA](../../prompts/anime-ja.md) |
| [`paper-cutout.png`](paper-cutout.png) | Paper Cutout | Overlapping polygonal paper pieces with paper texture and inner edges. | [EN](../../prompts/paper-cutout-en.md) / [JA](../../prompts/paper-cutout-ja.md) |

All six sheets are 768×768 RGBA (256×256 per cell). File sizes range from 219,140 to 284,646 bytes.

## Source

The six sheets were generated one style at a time with an external image-generation AI, from the current shared contract and each style block. The raw outputs are 1254×1254 RGBA. The model name and provider were not recorded, so this document does not guess them.

Only the normalized sheets are committed; the raw outputs stay outside the repository. The generation order was hand-drawn, pixel-art, iconic, retro-cartoon, anime, paper-cutout, and the contact sheet keeps that row order.

## Normalization

Normalization ran once in a script outside this repository; only the normalized PNGs are committed. For each raw sheet, the script:

1. labeled connected components to separate the nine figures and their effects from the background;
2. assigned every component (keyboard, sparkles, impact lines, sleep marks) to its pose;
3. applied one scale shared by all six styles, so character sizes stay comparable;
4. recomposed the poses into 768×768 with 256×256 cells, keeping a fixed feet baseline (y=208) and a fixed horizontal centre (x=128);
5. set every pixel with alpha 8 or below to 0.

As a result, no floating fragments remain, every cell keeps at least 43 px of transparent margin (the test requires 16 px), and all four corners of each sheet are fully transparent.

## Usage

Waddly bundles the six sheets and shows the idle frame of each one in the style chooser, so the selection is made on what the style actually looks like. The images also import like any other 3×3 sheet, but they are reference samples: importing one is not a guarantee of production quality. Copying a prompt uses the shared contract plus `prompts/<style>-<language>.md`, not these images.

## Known limitations

- **Occluded keyboard in pose 3.** In the focused pose the keyboard is partly behind the monitor in the source composition, so its left side is not visible. This is occlusion in the generated artwork, not a crop or a missing fragment.
- **Pixel Art keeps anti-aliasing.** The pixel-art source was generated with anti-aliasing. Pixels with alpha between 9 and 247 make up about 6.9% of the visible area (about 1.2% of the whole sheet), and there are 3,444 unique RGB values among them. The sheet was downscaled by a non-integer factor, so it does not sit on a strict integer pixel grid; enlarging it looks soft rather than crisp.
- **Per-style variation.** Each style was generated separately, so line weight and colors drift slightly between styles even though the poses and scale match.
- **Preview quality.** These are reference and preview samples, not validated production assets.

## Validation

[`Tests/WaddlyAppTests/CharacterStyleSampleTests.swift`](../../Tests/WaddlyAppTests/CharacterStyleSampleTests.swift), run with `mise run test`, checks every sample:

- it loads as a 768×768 sheet with 256×256 cells and a complete nine-frame set;
- every cell keeps a transparent margin of at least 16 px, and the sheet corners are transparent;
- all nine poses are distinct;
- the idle pose height stays within ±30% of the median across styles.

## Contact sheet

[`contact-sheet.png`](contact-sheet.png) (1206×1460 RGB, 686,574 bytes) is for review only. Its top panel uses the light background `#F7F7F7` and its bottom panel the dark background `#1C1C1E`, so transparency and edge fragments can be checked in both themes. Each panel shows six rows (styles, in generation order) by nine pose columns. `macos/build.sh` excludes this file from the app bundle.

---

# 画風サンプル

Waddlyの画風選択画面で使う、画風ごとに1枚ずつの参考スプライトシートです。各シートは、[`prompts/ja.md`](../../prompts/ja.md) の共通契約と各画風ブロックで指定した9ポーズを3×3に並べたものです。

## ファイル一覧

| ファイル | 画風 | 見た目 | プロンプト |
| --- | --- | --- | --- |
| [`pixel-art.png`](pixel-art.png) | ピクセルアート | 限定パレットと硬いエッジの16-bit機風ピクセルアート。 | [EN](../../prompts/pixel-art-en.md) / [JA](../../prompts/pixel-art-ja.md) |
| [`hand-drawn.png`](hand-drawn.png) | 手描き | 有機的で少し揺らぐ線に、フラットな塗りとステッカー風の仕上げ。 | [EN](../../prompts/hand-drawn-en.md) / [JA](../../prompts/hand-drawn-ja.md) |
| [`iconic.png`](iconic.png) | ミニマル | 太く単純化したシルエット、一定の線幅、フラットな塗り。 | [EN](../../prompts/iconic-en.md) / [JA](../../prompts/iconic-ja.md) |
| [`retro-cartoon.png`](retro-cartoon.png) | レトロカートゥーン | 太いインク線、丸みのある形、パイカット眼、落ち着いた配色。 | [EN](../../prompts/retro-cartoon-en.md) / [JA](../../prompts/retro-cartoon-ja.md) |
| [`anime.png`](anime.png) | アニメ | セルシェーディング、先細りの線、重なった瞳のハイライト。 | [EN](../../prompts/anime-en.md) / [JA](../../prompts/anime-ja.md) |
| [`paper-cutout.png`](paper-cutout.png) | 切り絵 | 多角形の紙片の重なり、紙の繊維感、内側の縁。 | [EN](../../prompts/paper-cutout-en.md) / [JA](../../prompts/paper-cutout-ja.md) |

6枚とも 768×768 RGBA（セルは256×256）。ファイルサイズは219,140〜284,646 bytesです。

## 出典

6枚は外部の画像生成AIで画風ごとに個別生成したものです。生成時の入力は現在の共通契約と各画風ブロックです。生成元は1254×1254 RGBAで、モデル名と提供元は記録していないため、この文書では推測しません。

コミットしているのは正規化後のシートだけで、生成元はリポジトリ外にあります。生成順は hand-drawn、pixel-art、iconic、retro-cartoon、anime、paper-cutout で、コンタクトシートの行もこの順です。

## 正規化

正規化はリポジトリ外のスクリプトで一度だけ行い、正規化済みのPNGだけをコミットしています。各生成元について、スクリプトは次の処理をします。

1. 連結成分ラベリングで9体のキャラクターと効果（キーボード、きらめき、衝撃線、睡眠の記号）を背景から分離する。
2. 各成分を対応するポーズへ割り当てる。
3. 6画風で共通のスケールを適用し、キャラクターの大きさをそろえる。
4. 768×768（256×256セル）へ再配置する。足元のベースラインは y=208、水平中心は x=128 に固定する。
5. alpha 8以下の画素を0にする。

この結果、浮遊する断片は残っておらず、各セルには43px以上の透明余白（テストの要求は16px以上）があり、各シートの四隅は完全に透明です。

## 用途

Waddlyは6枚を同梱し、画風選択画面で各シートのidleフレームをプレビュー表示します。そのため、画風は実際の見た目で選べます。3×3シートとしてインポートもできますが、これらは参考サンプルであり、インポートした画像の品質を保証するものではありません。プロンプトのコピーには、共通契約と `prompts/<style>-<language>.md` を使い、これらの画像は使いません。

## 既知の制限

- **3コマ目のキーボードの遮蔽。** focused のポーズでは、生成元の構図でキーボードがモニタの陰になり、左側が見えません。これは生成画像側の遮蔽であり、画像の切断や欠落ではありません。
- **Pixel Art のアンチエイリアス残存。** ピクセルアートの生成元にはアンチエイリアスが含まれています。alpha 9〜247 の画素は可視部分の約6.9%（シート全体の約1.2%）で、その中のユニークRGBは3,444色です。非整数倍の縮小のため整数ピクセルグリッドには乗っておらず、拡大するとピクセルアートらしい硬さは出ません。
- **画風ごとの揺れ。** 画風ごとに個別生成しているため、ポーズとスケールはそろっていても、線の太さや色はわずかに異なります。
- **プレビュー品質。** これらは参考・プレビュー用のサンプルで、検証済みの製品アセットではありません。

## 検証

[`Tests/WaddlyAppTests/CharacterStyleSampleTests.swift`](../../Tests/WaddlyAppTests/CharacterStyleSampleTests.swift)（`mise run test` で実行）が、6画風すべてについて次を検証します。

- 768×768・256×256セルのシートとして読み込め、9コマが揃っている。
- 各セルの透明余白が16px以上あり、シートの四隅が透明である。
- 9ポーズがすべて異なる。
- idleポーズの高さが、画風間の中央値の±30%以内に収まる。

## コンタクトシート

[`contact-sheet.png`](contact-sheet.png)（1206×1460 RGB、686,574 bytes）はレビュー用です。上段は明るい背景 `#F7F7F7`、下段は暗い背景 `#1C1C1E` で、透過とセル境界の断片を両方のテーマで確認できます。各段は生成順の6画風×9ポーズです。`macos/build.sh` はこのファイルをアプリバンドルから除外します。
