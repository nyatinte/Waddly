# Share dialog renders

Rendered, not captured. Every PNG here was produced by
[`ShareSnapshotTests`](../../Tests/WaddlyAppTests/ShareSnapshotTests.swift) drawing the app's own AppKit
views into a bitmap; none of them is an operating-system screenshot and nothing in this folder was
checked by hand. The dialog runs with `WindowPresenter.live` but its window is parked at
(-4000, -4000), uses the repository example sprite sheet (`assets/examples/nyatinte-bot-3x3.png`) and a
throwaway preference domain, so no user images or real preferences are involved.

| File | Source revision | State |
| --- | --- | --- |
| `dialog-before-{en,ja}-{light,dark}.png` | `b0e69e7`, before the share redesign | ready, pre-change controls |
| `dialog-after-{en,ja}-{light,dark}.png` | head of the change that adds this file | ready, native copy/post buttons |
| `state-hover-en-light.png` | same as `dialog-after-*` | Copy video hovered |
| `state-working-en-light.png` | same | generating: spinner, post disabled |
| `state-copied-en-light.png` | same | “Video copied” beside the video card |
| `state-copy-failed-en-light.png` | same | “Couldn’t copy. Try again.” beside the image card |
| `state-composer-failed-en-light.png` | same | composer could not open |
| `state-failed-en-light.png` | same | generation failed, native “Try Again” |
| `state-failed-ja-dark.png` | same | generation failed, Japanese, dark |

Regenerate the after/state set after any share-dialog change:

```sh
WADDLY_CAPTURE_SHARE=1 ./macos/test.sh --filter ShareSnapshotTests
```

The `dialog-before-*` files predate the change (`b0e69e7`) and are kept as the comparison side; do not
regenerate them from current code. `docs/SHARE.md` describes the flow, the state matrix, and the
verification gaps; this file only records where the pictures come from.
