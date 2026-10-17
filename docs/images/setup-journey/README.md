# First-run Pet step renders

Native AppKit content-view renders (`cacheDisplay(in:to:)`) composited onto the window's semantic
background and scaled to at most 1400 pixels on the long edge. These are **not** screen captures, not
manual QA, and not proof of keyboard, VoiceOver, or interaction testing. Each render was built from
`git archive` of the named revision in a temporary capture harness, using the repository's example
sheet (`assets/examples/nyatinte-bot-3x3.png`) as the sample pet, isolated temporary preferences, and
no user pet, key codes, or preferences.

Surface: the Setup Guide **Pet step** (fresh install, no pet stored), which is where this branch adds
the explicit “Try the sample pet first” shortcut.

| File | Revision | State | Language | Appearance |
| --- | --- | --- | --- | --- |
| `before-86dfce5-en-light.png` | `86dfce5` | Pet step, no pet; two import options | English | light |
| `before-86dfce5-en-dark.png` | `86dfce5` | Pet step, no pet; two import options | English | dark |
| `before-86dfce5-ja-light.png` | `86dfce5` | Pet step, no pet; two import options | Japanese | light |
| `before-86dfce5-ja-dark.png` | `86dfce5` | Pet step, no pet; two import options | Japanese | dark |
| `after-d4bc89b-en-light.png` | `d4bc89b` | Pet step, no pet; sample shortcut added | English | light |
| `after-d4bc89b-en-dark.png` | `d4bc89b` | Pet step, no pet; sample shortcut added | English | dark |
| `after-d4bc89b-ja-light.png` | `d4bc89b` | Pet step, no pet; sample shortcut added | Japanese | light |
| `after-d4bc89b-ja-dark.png` | `d4bc89b` | Pet step, no pet; sample shortcut added | Japanese | dark |
| `after-sample-d4bc89b-en-light.png` | `d4bc89b` | Pet step, sample chosen; “sample is active” message | English | light |
| `after-sample-d4bc89b-en-dark.png` | `d4bc89b` | Pet step, sample chosen; “sample is active” message | English | dark |
| `after-sample-d4bc89b-ja-light.png` | `d4bc89b` | Pet step, sample chosen; “sample is active” message | Japanese | light |
| `after-sample-d4bc89b-ja-dark.png` | `d4bc89b` | Pet step, sample chosen; “sample is active” message | Japanese | dark |

`before` is the #94 setup-feedback head `86dfce5`; `after` is the sample-shortcut commit `d4bc89b`.
The `after-sample` state was set by pointing the fixture's pet store at the sample frames and marking
the page sample-active; it shows what the page says after the shortcut is chosen.

The default-font English/dark and Japanese/light Pet-step renders were inspected for text and footer
clipping: the added shortcut and the sample-active line stay inside the fixed 820 × 520 layout, and the
footer button remains visible. Larger text, increased contrast, VoiceOver speech, keyboard navigation,
Reduce Motion, and the System Settings hand-off remain manual QA items and are not claimed here.
