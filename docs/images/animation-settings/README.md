# Animation Settings editor snapshots

Native view snapshots of the Animation Settings window, before and after the SwiftUI migration
(#95). They are **not** screen captures: each window's content view was rendered with AppKit's
`cacheDisplay(in:to:)` and composited onto the window's semantic `backgroundColor`, because
screen-capture permission is unavailable in the capture environment.

| File | Revision | UI | Language | Appearance |
| --- | --- | --- | --- | --- |
| `before-appkit-f1918a0-ja-light.png` / `-dark.png` | `f1918a0` | AppKit rows | 日本語 | light / dark |
| `before-appkit-f1918a0-en-light.png` / `-dark.png` | `f1918a0` | AppKit rows | English | light / dark |
| `after-swiftui-c5f8fcf-ja-light.png` / `-dark.png` | `c5f8fcf` | SwiftUI | 日本語 | light / dark |
| `after-swiftui-c5f8fcf-en-light.png` / `-dark.png` | `c5f8fcf` | SwiftUI | English | light / dark |

Provenance: generated from `git archive` of the named revisions with a local capture harness, using
the `assets/examples/nyatinte-bot-3x3.png` example pet. The `after` revision is the migration commit;
the editor's default 760 × 700 content is unchanged by the later `contentMinSize` minimum fix, so
these `after` images still show the current default layout. The original high-density captures are
scaled to a maximum of 1600 pixels and losslessly recompressed for documentation.

Not verified by these images: keyboard navigation, focus order, and VoiceOver output were not
manually exercised; the snapshots show the initially rendered layout only.
