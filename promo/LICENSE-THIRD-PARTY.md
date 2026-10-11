# Third-party notices — Waddly promo

The rendered video is 30 seconds of motion graphics drawn entirely in this
project. It ships no Apple wallpaper, icon, font, sound or other third-party
artwork. Two third-party components are used to *build* it.

## GSAP 3.14.2 — `vendor/gsap.min.js`

Copyright (c) 2008-2025, GreenSock. All rights reserved.

GSAP is distributed under the "Standard GreenSock License": it is free to use,
including in commercial and client work, as long as you are not selling the
library itself or a product whose primary value is the library. See
<https://gsap.com/standard-license/>.

The file is vendored (not loaded from a CDN) so renders are reproducible
offline.

## Noto Sans JP — `assets/fonts/NotoSansJP.ttf`

Copyright 2014-2025 Adobe (<http://www.adobe.com/>), with Reserved Font Name
"Source". Noto is a trademark of Google LLC.

Licensed under the **SIL Open Font License, Version 1.1**. The full licence
text is at <https://openfontlicense.org/open-font-license-official-text/>.

Summary of the terms that matter here:

- The font may be used, studied, modified and redistributed freely, including
  bundled with software, as long as it is not sold by itself.
- Rendered glyphs in the video are not a redistribution of the font software
  and need no further action.
- If the `.ttf` file itself is redistributed, this notice and the OFL text must
  travel with it. The file is therefore **not committed to git** — fetch it with
  `tools/fetch-font.sh`.

## Assets from the Waddly repository

- `assets/pets/nyatinte-bot-3x3.png` and `assets/brand/*.png` are the app
  author's own artwork. Per the repository [README](../../README.md), the app
  icon, example images and demo GIF are **not** covered by the MIT licence and
  reuse should be confirmed with the author.
- Everything else on screen — the wallpaper gradient, menu bar, Dock, desktop
  icons, keycaps, pointer and wordmark — is drawn from scratch in
  `styles/main.css` and `scripts/desktop.js`.

## Deliberately not used

- Apple wallpapers, SF Symbols, application icons, the Apple logo, and the
  system UI font. The menu bar, Dock and pointer are original drawings, not
  screenshots or extracts.
- Any audio. The video is silent by design.
