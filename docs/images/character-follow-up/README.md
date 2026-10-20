# #124 follow-up: real window captures and native read-back

See [the session report](../../character-import-follow-up.md) for steps, exact source revisions,
observations and limitations. `captures.json` records each original PNG's SHA-256, source revision,
ScreenCaptureKit window ID and scale. These are live macOS windows, not cached/off-screen renders.
All are dark; the before Setup and after Change Character captures are not a matched pixel diff.

`native-ax-ja.json` and `native-ax-en.json` are selected native editor-button attribute read-backs
(31 each: 27 frame actions and four Add controls). `minimize-native.txt` records native window
minimization before/after menu refocus. `applied-manifest.json` is the isolated development variant's
on-disk manifest after native Apply; it is not production pet data. No user clipboard or unrelated
Finder/open-panel content is included.

The screenshots show rows/layout and actual saved/staged transitions. They do **not** show a hover
help popover; help text is proved only by `AXHelp` read-back. Physical keyboard, VoiceOver,
Finder/category drag, light/contrast/Reduce Motion and full memory-budget acceptance remain open.
