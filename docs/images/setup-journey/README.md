# First-run Pet and Keyboard-reactions renders

Native AppKit content-view renders (`cacheDisplay(in:to:)`) composited onto the window's semantic
background and scaled to at most 1400 pixels on the long edge. These are **not** screen captures, not
manual QA, and not proof of keyboard, VoiceOver, or interaction testing. Each render was built from
`git archive` of the named revision in a temporary capture harness, using the repository's example
sheet (`assets/examples/nyatinte-bot-3x3.png`) as the sample pet, isolated temporary preferences, and
no user pet, key codes, or preferences.

Surfaces: the Setup Guide **Pet step** (fresh install, no pet stored), where this change adds the
explicit “Try the sample pet first” shortcut, and the **Keyboard reactions step**, where it adds the
observed-reaction confirmation.

| File | Revision | State | Language | Appearance |
| --- | --- | --- | --- | --- |
| `before-e7a026d-en-light.png` | `e7a026d` | Pet step, no pet; two import options | English | light |
| `before-e7a026d-en-dark.png` | `e7a026d` | Pet step, no pet; two import options | English | dark |
| `before-e7a026d-ja-light.png` | `e7a026d` | Pet step, no pet; two import options | Japanese | light |
| `before-e7a026d-ja-dark.png` | `e7a026d` | Pet step, no pet; two import options | Japanese | dark |
| `after-5bf0baf-en-light.png` | `5bf0baf` | Pet step, no pet; sample shortcut added | English | light |
| `after-5bf0baf-en-dark.png` | `5bf0baf` | Pet step, no pet; sample shortcut added | English | dark |
| `after-5bf0baf-ja-light.png` | `5bf0baf` | Pet step, no pet; sample shortcut added | Japanese | light |
| `after-5bf0baf-ja-dark.png` | `5bf0baf` | Pet step, no pet; sample shortcut added | Japanese | dark |
| `after-sample-5bf0baf-en-light.png` | `5bf0baf` | Pet step, sample chosen; “sample is active” message | English | light |
| `after-sample-5bf0baf-en-dark.png` | `5bf0baf` | Pet step, sample chosen; “sample is active” message | English | dark |
| `after-sample-5bf0baf-ja-light.png` | `5bf0baf` | Pet step, sample chosen; “sample is active” message | Japanese | light |
| `after-sample-5bf0baf-ja-dark.png` | `5bf0baf` | Pet step, sample chosen; “sample is active” message | Japanese | dark |
| `monitoring-awaiting-5bf0baf-en-light.png` | `5bf0baf` | Keyboard reactions, tap live, no key yet; Next disabled | English | light |
| `monitoring-awaiting-5bf0baf-en-dark.png` | `5bf0baf` | Keyboard reactions, tap live, no key yet; Next disabled | English | dark |
| `monitoring-awaiting-5bf0baf-ja-light.png` | `5bf0baf` | Keyboard reactions, tap live, no key yet; Next disabled | Japanese | light |
| `monitoring-awaiting-5bf0baf-ja-dark.png` | `5bf0baf` | Keyboard reactions, tap live, no key yet; Next disabled | Japanese | dark |
| `monitoring-confirmed-5bf0baf-en-light.png` | `5bf0baf` | Keyboard reactions, key delivered; confirmed | English | light |
| `monitoring-confirmed-5bf0baf-en-dark.png` | `5bf0baf` | Keyboard reactions, key delivered; confirmed | English | dark |
| `monitoring-confirmed-5bf0baf-ja-light.png` | `5bf0baf` | Keyboard reactions, key delivered; confirmed | Japanese | light |
| `monitoring-confirmed-5bf0baf-ja-dark.png` | `5bf0baf` | Keyboard reactions, key delivered; confirmed | Japanese | dark |

`before` is `origin/main` `e7a026d` (release v1.3.0); `after` and the other states are rendered at
`5bf0baf`, the source head that adds the sample shortcut and the observed-reaction confirmation (and
the pending-import guard those need). The `after-sample` state points the fixture's pet store at the
sample frames and marks the page sample-active. The two `monitoring-*` renders use a live tap with the
fixture's observation flag false (awaiting) or true (confirmed); they do not involve a real key event,
so they illustrate the state labels, not a live typing session. The pending-import guard and the
paused-observation fix are control-flow only: they change which state is shown, not the layout or copy
of the five rendered states. Because the Pet step resting layout is unchanged, the earlier
`before-86dfce5`/`after-2b70ed0` renders from the pre-mainline branch were replaced by these
mainline-provenanced files.

The default-font English/dark and Japanese/light renders of each surface were inspected for text and
footer clipping: the shortcut, the sample-active line, the “waiting for a key press” status, and the
confirmed status all stay inside the fixed 820 × 520 layout, and the footer buttons remain visible.
Larger text, increased contrast, VoiceOver speech, keyboard navigation, Reduce Motion, and the System
Settings hand-off remain manual QA items and are not claimed here.
