# Character-import renders

Native AppKit content-view renders (`cacheDisplay(in:to:)`) composited onto the appearance's window
background, bounded to 1400 pixels on the long edge. These are **not** screen captures, not manual
QA, and not proof of keyboard, VoiceOver, contrast, Larger Text, Reduce Motion, or live-interaction
behavior. No live interaction occurred: every state was set through the model or the embedded
AppKit preview pane.

The original 40 renders retain their source attribution to `023474df4252aa4a03b3a3e25119ba9714e4ddad`
(`test(import): cover drop routing, stale acquisitions, and the store commit`). Those existing PNGs
remain byte-identical; this capture adds eight states from behavior source
`bacc8eec1dc3d2464dccf20c9913b44fd3c7f40b`, without relabeling the original assets.

## How they were produced

- `WADDLY_CAPTURE_CHARACTER_IMPORT=1 ./macos/test.sh --no-parallel --filter CharacterImportSnapshotTests`
- `Tests/WaddlyAppTests/CharacterImportSnapshotTests.swift` builds each state on a real
  `CharacterImportWindowController` (Change Character host) or `SetupWizardController` (Setup Pet
  step host) with the repository's isolated test preferences, the example sheet
  `assets/examples/nyatinte-bot-3x3.png` as the staged pet, and an isolated named pasteboard. No user
  pet, user preferences, key codes, or input data are involved.
- `Tests/WaddlyAppTests/CaptureHarness.swift` renders the content view, composites it onto the
  appearance background, scales it, and writes the PNG. With the environment variable unset the
  suite does nothing, so `mise run test` stays side-effect free.
- English `AppLanguage.english`, Japanese `AppLanguage.japanese`; light `NSAppearance.aqua`, dark
  `NSAppearance.darkAqua`.

Two harness notes, stated so the evidence is not over-read:

- The valid/per-pose renders push the staged frames into the embedded AppKit preview pane and sleep
  250 ms so the preview player's first frame publishes off screen. The live app reaches the same
  state through the representable's normal update pass; the render only pins the frame that would be
  showing.
- The advanced-editor renders show `CharacterFrameEditor` (the reused `AnimationSettingsView`
  over the staged draft) as an off-screen `NSHostingView`, not the sheet chrome.
- The harness discards the staged draft before closing the Change Character window, because the
  shipped window now asks before discarding a dirty close; no dialog is part of any render.

## Surfaces

Change Character host (`change-*`), 880 × 580 pt content:

| State | File stem | Shows |
| --- | --- | --- |
| Empty drop zone | `change-empty` | dashed drop zone, Choose File / Paste, disabled Apply |
| Drag eligible | `change-drag-hover` | accent-highlighted zone and “Drop to import” copy |
| Clipboard ready | `change-clipboard-ready` | Paste at full emphasis; no error |
| Clipboard empty | `change-clipboard-empty` | subdued Paste and the inline “No image on the clipboard.” after an attempted paste |
| Valid staged | `change-valid` | animated per-pose preview, source name/dimensions/cell size, positive status |
| Valid, nine cells | `change-valid-nine-cells` | the same staged sheet in the pane's 9-cell mode |
| Invalid import | `change-invalid` | inline “could not be read as a PNG.” with the staged candidate still present |
| Advanced editor | `change-editing` | Idle/Typing/Sleep/Enter rows with Add, remove, and move controls over the staged draft |
| Saved character | `change-saved-character` | The saved pet is immediately previewed and the advanced edit entry is available without source metadata; the test fixture exercises a nonstandard per-category frame count |
| Declined commit | `change-rejected-commit` | Localized inline feedback distinct from save failure; draft retained |

Setup Pet step host (`setup-*`), 820 × 520 pt content:

| State | File stem | Shows |
| --- | --- | --- |
| Empty | `setup-empty` | step progress row above the shared empty screen |
| Valid staged | `setup-valid` | staged preview with the shared screen's Cancel + Continue |

Each stem has `-en-light`, `-en-dark`, `-ja-light`, `-ja-dark` variants (10 original states + 2 added states = 48 files). The added eight files were captured with `WADDLY_CAPTURE_CHARACTER_IMPORT=1 ./macos/test.sh --no-parallel --filter CharacterImportSnapshotTests`; the run completed with four tests in one suite passing after 28.777 seconds.

## Not claimed here

VoiceOver speech and element order, keyboard/Tab/Space/Return/Escape traversal, increased contrast,
Larger Text/dynamic type without clipping, Reduce Motion, a real drag session, a real pasteboard
paste, a real file picker, and the live apply/cancel transitions were not exercised. The renders
illustrate the documented states; the manual QA items in `docs/ux-interaction-audit.md` remain open.
