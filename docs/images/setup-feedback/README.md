# Setup feedback snapshots

Native AppKit content-view renders (`cacheDisplay(in:to:)`) composited onto the window's semantic background and scaled to at most 1400 pixels. These are not screen captures or proof of keyboard/VoiceOver/manual interaction testing. Source was built from `git archive` in a temporary capture harness using the repository's example pet and isolated temporary preferences; no user pet or preferences were used.

- `before-f1918a0-*`: original Pet selection at `f1918a0`.
- `after-0c33664-*`: ChatGPT guide at `0c33664`, with browser-open failure and import-failure state explicitly set in the harness. The two states are deliberately shown together to inspect the worst-case default-font layout, not to imply a live browser failure was reproduced.
- `en-light`: English/light appearance; `ja-dark`: Japanese/dark appearance.

Both after renders were inspected for clipped text/footer overlap at the supported default size and font. Larger text, other states, actual spoken announcements, keyboard navigation, and the System Settings hand-off remain unverified. The light render also shows the preview backdrop following the window appearance rather than retaining its previously resolved dark CGColor.
