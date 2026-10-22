# Character-import renders

Native AppKit content-view renders (`cacheDisplay(in:to:)`) composited onto the appearance's window
background, bounded to 1400 pixels on the long edge. These are **not** screen captures, not manual
QA, and not proof of keyboard, VoiceOver, contrast, Larger Text, Reduce Motion, or live-interaction
behavior. No live interaction occurred: every state was set through the model or the embedded
AppKit preview pane.

The original 40 renders retain their source attribution to `023474df4252aa4a03b3a3e25119ba9714e4ddad`
(`test(import): cover drop routing, stale acquisitions, and the store commit`), and the eight states
added later were captured from `bacc8eec1dc3d2464dccf20c9913b44fd3c7f40b`. **Every file in this
directory now shows the setup-UI layout change in this branch**: the Change Character window is
1040 × 640 pt (resizable above that minimum), import lives in one drop zone, a staged sheet collapses
to a file card, and Cancel/Apply sit in a pinned footer above a divider. Earlier revisions therefore
describe older pixels, not the current ones.

The frame-editor render set was captured after issue #151 replaced the per-frame add/remove/reorder editor with the 3×3 crop and alignment editor; the old `change-editing-*` renders were removed rather than left to describe a surface that no longer ships.

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

Harness notes, stated so the evidence is not over-read:

- The valid/per-pose, saved-character, and declined-commit renders push the staged frames into the
  embedded AppKit preview pane and sleep 250 ms so the preview player's first frame publishes off
  screen. The live app reaches the same state through the representable's normal update pass; the
  render only pins the frame that would be showing.
- The frame-editor renders show the real `CharacterFrameEditor` as an off-screen `NSHostingView`
  at its 1320 × 800 pt preferred size (or 1040 × 700 pt for the compact surface), with the example
  sheet prepared through `CharacterImportModel`/`CharacterFrameEditorModel`. They are not the
  attached-sheet chrome the live window uses. The captures pin `colorScheme` to the appearance
  because AppKit appearance alone does not reach the SwiftUI environment in an off-screen host.


- The harness discards the staged draft before closing the Change Character window, because the
  shipped window now asks before discarding a dirty close; no dialog is part of any render.

## Surfaces

Change Character host (`change-*`), 1040 × 640 pt content:

| State | File stem | Shows |
| --- | --- | --- |
| Empty drop zone | `change-empty` | one dashed zone with Choose File and Paste from Clipboard inside it, the “Import a PNG to start editing.” hint, and a disabled Apply in the pinned footer |
| Drag eligible | `change-drag-hover` | accent-highlighted zone and “Drop to import” copy |
| Clipboard ready | `change-clipboard-ready` | the in-zone Paste link at full emphasis; no error |
| Clipboard empty | `change-clipboard-empty` | subdued Paste and the inline “No image on the clipboard.” after an attempted paste |
| Valid staged | `change-valid` | the zone collapsed to one file card (name, Ready to apply, dimensions/cell size, Replace, Adjust frames…, and the paste link that keeps ⌘V replacing) beside the animated preview |
| Valid, nine cells | `change-valid-nine-cells` | the same staged sheet in the pane's 9-cell mode |
| Invalid import | `change-invalid` | inline “could not be read as a PNG.” below the retained file card |
| Saved character | `change-saved-character` | The saved pet is previewed and the card reads “Current character” with its frame count; Replace is available, and Adjust frames… is disabled with re-import guidance for the fixture’s nonstandard per-category frame count |
| Declined commit | `change-rejected-commit` | Localized inline feedback distinct from save failure; draft and card retained |



Setup Pet step host (`setup-*`), 820 × 520 pt content:

| State | File stem | Shows |
| --- | --- | --- |
| Empty | `setup-empty` | step progress row above the shared empty screen |
| Valid staged | `setup-valid` | staged preview with the shared screen's Cancel + Continue |

Each stem has `-en-light`, `-en-dark`, `-ja-light`, `-ja-dark` variants (10 original states + 2 added states = 48 files). The added eight files were captured with `WADDLY_CAPTURE_CHARACTER_IMPORT=1 ./macos/test.sh --no-parallel --filter CharacterImportSnapshotTests`; the snapshot suite now runs six capture tests in one suite.

## Frame-editor renders (`frame-editor-*`), 1320 × 800 pt or 1040 × 700 pt content

| State | File stem | Shows |
| --- | --- | --- |
| Default crop | `frame-editor-default` | Frame 01 selected, square crop with eight handles, 3×3 guides and marked center crosshair, source-sheet context dimmed outside the crop, Before = After |
| Crop edit | `frame-editor-crop` | Frame 04 with a smaller crop and a content offset; the output canvas stays 256 × 256 px while the crop only narrows the visible frame, and the edited markers are visible |
| Align edit, neighbour warning | `frame-editor-align` | Align tool selected, D-pad and signed X/Y fields, crop extended past the cell with the dashed warning border and inline warning |
| Legacy saved frames | `frame-editor-legacy` | A pet without its original sheet: per-frame fallback, no sheet source line, and the re-import explanation in the sidebar |
| Compact layout | `frame-editor-compact` | 1040 × 700 pt window: the navigator collapses to a numbered frame rail while the canvas and inspector stay usable |

Each stem has `-en-light`, `-en-dark`, `-ja-light`, `-ja-dark` variants (20 files). The compact and
legacy states are produced by `capturesFrameEditorLegacyAndCompactSurfaces`.

## Not claimed here

VoiceOver speech and element order, keyboard/Tab/Space/Return/Escape traversal, increased contrast,
Larger Text/dynamic type without clipping, Reduce Motion, a real drag session, a real pasteboard
paste, a real file picker, and the live apply/cancel transitions were not exercised. The renders
illustrate the documented states; the manual QA items in `docs/ux-interaction-audit.md` remain open.
