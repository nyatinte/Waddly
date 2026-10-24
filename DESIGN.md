---
version: alpha
name: Waddly
description: A native macOS pixel pet that reacts to typing. Calm, native, private, and accessible.
colors:
  primary: "#000000"
  secondary: "#6E6E73"
  tertiary: "#B0B0B5"
  neutral: "#FFFFFF"
  accent: "#007AFF"
  positive: "#1F7A33"
  positive-dark: "#4ADE80"
  critical: "#C62828"
  critical-dark: "#FF7B72"
  warning: "#B25000"
  warning-dark: "#FFB340"
  brand-x: "#000000"
  brand-x-on: "#FFFFFF"
  brand-x-disabled-light: "#EBEBEB"
  brand-x-disabled-light-content: "#656565"
  brand-x-disabled-dark: "#424242"
  brand-x-disabled-dark-content: "#B6B6B6"
typography:
  display:
    fontFamily: SF Pro Display
    fontSize: 25px
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: SF Pro Text
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.3
  heading:
    fontFamily: SF Pro Text
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: SF Pro Text
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
  callout:
    fontFamily: SF Pro Text
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.35
  caption:
    fontFamily: SF Pro Text
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.3
  action:
    fontFamily: SF Pro Text
    fontSize: 13px
    fontWeight: 500
    lineHeight: 1
  mono:
    fontFamily: SF Mono
    fontSize: 11px
    fontWeight: 500
    lineHeight: 1.2
spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  xxl: 24px
  xxxl: 32px
  content-inset: 24px
  section-gap: 16px
  column-gap: 20px
  action-gap: 8px
  action-height: 36px
  control-height: 28px
  footer-inset: 12px
  preview-width: 360px
  hit-target-min: 20px
rounded:
  sm: 6px
  md: 8px
  lg: 12px
  preview: 16px
  full: 9999px
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    height: 36px
    padding: 12px
  button-secondary:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    height: 36px
    padding: 12px
  button-brand-x:
    backgroundColor: "{colors.brand-x}"
    textColor: "{colors.brand-x-on}"
    rounded: "{rounded.full}"
    height: 36px
    padding: 12px
  button-brand-x-disabled-light:
    backgroundColor: "{colors.brand-x-disabled-light}"
    textColor: "{colors.brand-x-disabled-light-content}"
    rounded: "{rounded.full}"
    height: 36px
    padding: 12px
  button-brand-x-disabled-dark:
    backgroundColor: "{colors.brand-x-disabled-dark}"
    textColor: "{colors.brand-x-disabled-dark-content}"
    rounded: "{rounded.full}"
    height: 36px
    padding: 12px
  card:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
    padding: 16px
  option-card:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
    padding: 14px
    height: 72px
  footer:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.secondary}"
    height: 36px
    padding: 12px
  auxiliary-control:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    height: 28px
    padding: 8px
  status-positive:
    textColor: "{colors.positive}"
  status-pending:
    textColor: "{colors.secondary}"
  status-critical:
    textColor: "{colors.critical}"
  status-warning:
    textColor: "{colors.warning}"
  status-positive-dark:
    textColor: "{colors.positive-dark}"
  status-critical-dark:
    textColor: "{colors.critical-dark}"
  status-warning-dark:
    textColor: "{colors.warning-dark}"
---

# Waddly Design System

## Overview

Waddly is a native macOS pixel pet: a small character that lives on the desktop and reacts to typing. The product is quiet by default. The pet is the only playful, decorative surface; every window, menu, alert, and editor around it should feel like macOS, not like a themed web app.

The system follows Apple's Human Interface Guidelines: native controls, semantic colors, the system font, standard windows and menus, a single obvious primary action, and accessibility as a baseline rather than a later pass. The visual identity is deliberately thin: black/white pixel art, a calm neutral chrome, one accent color, and one brand exception for the X share action.

**Principles**

1. **Native first.** Use AppKit/SwiftUI controls and standard window chrome. Custom views earn their place only when the product needs something AppKit cannot express (the pet, the drag guide, the checkerboard preview, the X brand pill).
2. **One primary action per screen.** The primary action is 36 pt, accent-filled, and the default action. Secondary actions are equal in height but quieter.
3. **Clarity over decoration.** Depth comes from native window layering, tonal surfaces, and 1 px separators, not shadows or gradients.
4. **Private by default.** Key codes exist only inside the event tap to identify Enter. Never store, log, or transmit them; keep images local.
5. **Accessible by default.** Every control has a label, every status is more than color, every animation respects Reduce Motion, and every action is reachable from the keyboard.
6. **No surface is exempt.** The Setup Guide, Character Import, Frame Editor, Share dialog, menus, alerts, and the pet panel all follow this document. The Frame Editor is a dense workspace, not a separate design language.

**Reference:** [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) — Foundations (Accessibility, Color, Dark Mode, Layout, Motion, Privacy, Typography) and Components (Buttons, Menus, Alerts, Windows). The numeric tokens below are the Waddly values; where the HIG gives a default (macOS 13 pt body, 28 × 28 pt default control, 20 × 20 pt minimum), this document narrows it, never widens it.

**Source of truth.** The tokens in the front matter are normative values. The prose is normative intent. The implementation lives in `Sources/WaddlyApp/LayoutMetrics.swift` and the component files named in each section. If code and this document disagree, fix one of them in the same change; do not quietly add a third value.

## Colors

Waddly uses macOS semantic colors for chrome and text, and a small set of explicit tokens for brand and status. Semantic colors already carry Light, Dark, Increase Contrast, and accent-color behavior; do not replace them with fixed RGB values.

| Role | Token / NSColor | Use |
| --- | --- | --- |
| Primary text | `primary` / `labelColor` | Headings, body, action labels |
| Secondary text | `secondary` / `secondaryLabelColor` | Captions, metadata, instructions |
| Tertiary text | `tertiary` / `tertiaryLabelColor` | Non-essential metadata and placeholders only; never instructions or status |
| Surface | `neutral` / `windowBackgroundColor` | Window background |
| Card surface | `controlBackgroundColor` | Cards, option cards, preview backdrops |
| Separator | `separatorColor` | 1 px dividers, card borders, drop-zone outlines |
| Accent | `accent` / `controlAccentColor` | Primary actions, links, focus, selection |
| Positive | `positive` / `positive-dark` | Positive status text and icons; Light `#1F7A33`, Dark `#4ADE80` |
| Critical | `critical` / `critical-dark` | Errors and destructive confirmation; Light `#C62828`, Dark `#FF7B72` |
| Warning | `warning` / `warning-dark` | Recoverable warnings; Light `#B25000`, Dark `#FFB340` |
| X brand | `brand-x` / `brand-x-on` | X share action only |
| X disabled | `brand-x-disabled-*` | Disabled X share action, light and dark pairs |

**Contrast rules**

- Text up to 17 pt: **4.5:1 minimum**. 18 pt or bold: **3:1 minimum**. Check both Light and Dark, and again with Increase Contrast.
- System green/red are intended for icons and fills. The app's small positive/error text uses the accessible `positive` / `critical` (Light) or `positive-dark` / `critical-dark` (Dark) tokens; `Color.green` and `Color.red` are not text tokens. The migration API is `DesignTokens.Status`, added with the Frame Editor; it selects the pair for the current appearance. Setup and Character Import still use system green/red until migrated.
- Tertiary text is below 4.5:1 on purpose. It is reserved for metadata the user does not need to read to complete a task.
- Never convey state with color alone. A status is an icon + label (check/circle/triangle), and the label states the state in words.
- Resolve layer colors for the current appearance (`shareLayerColor` in `PetShareDialogComponents.swift`); a `CGColor` captured in one appearance is stale in the other.

**X brand exception.** The share action is X's brand, not Waddly's accent. Use the official X glyph as a template, black with white content in the Light appearance and white with black content in Dark. The disabled pairs are the contract values: Dark `#424242` fill / `#B6B6B6` content (≈5.0:1), Light `#EBEBEB` fill / `#656565` content (≈4.8:1). The current Share implementation uses calibrated white 0.90 fill / 0.30 content in Light and 0.20 / 0.72 in Dark, which render close to these values; migrating it to the exact sRGB tokens and asserting the contrast is part of the Frame Editor follow-up. Do not use `controlAccentColor` for this button, and do not alter the glyph shape.

**Checkerboard.** The transparency checkerboard is content, not chrome: `0.22` / `0.30` neutral tiles in Dark and `0.88` / `0.97` in Light. It appears only behind transparent pet previews.

**Do not:** hardcode white/black for text (the canvas crosshair and movie play overlay are the only intentional exceptions), use accent as a status color, or use a fixed RGB value where a semantic NSColor exists.

## Typography

Waddly uses the system font (SF Pro) exclusively. No custom fonts, no downloaded typefaces, no display faces. Use `NSFont.preferredFont(forTextStyle:)` or SwiftUI text styles where the layout allows; fixed point sizes are permitted only for dense editor surfaces and must use this scale.

| Token | Size / weight | Use |
| --- | --- | --- |
| `display` | 25 / 600 | Setup page title |
| `title` | 15 / 600 | Window and editor titles |
| `heading` | 13 / 600 | Card titles, section headings |
| `body` | 13 / 400 | Default body and descriptions |
| `callout` | 12 / 400 | Secondary descriptions and status lines |
| `caption` | 11 / 400 | Metadata, hints, inline error text |
| `action` | 13 / 500 | Button and menu labels |
| `mono` | 11 / 500 | Numeric editor values and dimensions |

**Rules**

- **Nothing below 11 pt.** Apple's macOS minimum for custom type is 10 pt; Waddly's floor is 11. The Frame Editor's 9 pt and 10 pt labels migrate to 11 pt.
- Use secondary/tertiary color to create hierarchy before reducing the size.
- Use the monospaced face only for numbers, dimensions, and canvas values; never for prose.
- Support the system's larger-text setting: prefer semantic text styles, allow text to wrap, and test at a larger text size. Fixed-height controls must grow or reflow, not clip.
- Localization: Japanese and English are first-class. Avoid truncating instructions; `docs` no longer exists, but the rule remains: recovery instructions are never ellipsized (see #154).
- Do not use font weight below 400. Do not use more than two weights on one screen.
- The DESIGN.md linter reports `button-primary` (accent with a white label) at 4.02:1. That is the macOS system-accent/white pair, not a fixed brand color: the native control uses the user's accent and Increase Contrast. The linter warning is expected; do not "fix" it by inventing a darker accent. All Waddly-authored status text must use the `positive`/`critical` accessible pairs.

## Layout

The layout uses a **4 pt base grid** and an **8 pt rhythm**, matching the macOS spacing system. Every window uses the same edge, section, column, action, and footer tokens.

| Token | Value | Use |
| --- | --- | --- |
| `xs` | 4 | Micro gaps, icon padding |
| `sm` | 8 | Default gap between related elements; action gap |
| `md` | 12 | Footer padding, tight groups |
| `lg` | 16 | Section padding, panel padding |
| `xl` | 20 | Comfortable column gap |
| `xxl` | 24 | Window content inset |
| `xxxl` | 32 | Major section separation |
| `content-inset` | 24 | Window edges, header, body, footer |
| `section-gap` | 16 | Heading block to content |
| `column-gap` | 20 | Two-column body |
| `action-gap` | 8 | Adjacent actions |
| `action-height` | 36 | Primary/secondary actions |
| `control-height` | 28 | Auxiliary and compact controls |
| `footer-inset` | 12 | Vertical padding around a pinned footer |
| `preview-width` | 360 | Preview column in Setup and Character Import |
| `hit-target-min` | 20 | Minimum clickable area; HIG macOS minimum |

**HIG constraints**

- macOS default control size is **28 × 28 pt**; the minimum is **20 × 20 pt**. Waddly uses 28 pt for auxiliary controls and 36 pt for actions; no clickable control may be smaller than 20 × 20 pt even when its visual is smaller (enlarge the hit area).
- Leave about 12 pt around bezeled controls and about 24 pt around bezel-less elements' visible edges. Use `action-gap` between actions and `section-gap` between groups.
- Prefer one primary action. Place it at the trailing edge of a pinned footer; secondary actions go to the leading edge. The share action is centered because it is the single action in that footer (see Components).

**Windows**

| Surface | Content size | Behavior |
| --- | --- | --- |
| Setup Guide | 820 × 520 | Fixed, non-restorable; progress header; pinned footer |
| Character Import / Change Character | 1040 × 640 | Resizable above the minimum; pinned footer |
| Frame Editor | 1320 × 800 preferred, 1040 × 700 minimum | Resizable; compact layout below 1160 pt |
| Share | 700 × 380 | Fixed; two equal cards; pinned footer |
| Pet panel | 180 / 240 / 320 square | Borderless, draggable, no window chrome |
| Permission guide | Setup size | Floats beside System Settings; manual steps fallback |

- Fixed windows must not be restorable to a stale frame; set `isRestorable = false` and re-assert the content size when shown.
- Resizable windows define a minimum that keeps the footer and every column visible. Do not let a resizable window reflow into a broken compact state; switch to the explicit compact layout instead (Frame Editor below 1160 pt).
- Every window centers on first show and remembers a user move only where the surface supports it (the pet panel and the permission guide).

**Dense workspace variant.** The Frame Editor is denser than the setup-class windows, but it uses the same tokens: `lg` 16 for the title bar and panel padding (the workspace is edge-to-edge and does not add a 24 pt window margin), `section-gap` between groups, `action-height` for Done and Reset, `control-height` for zoom/stepper/segmented controls, and the type/radius scales. `FrameEditorMetrics` may keep geometry that is specific to the canvas (sidebar 306, inspector 300/268, compact rail 58, breakpoint 1160, canvas reserves), but it may not introduce new spacing, type, control, or radius values. The current `outerPadding 16` becomes `lg`; the 9/10 pt labels become 11 pt; 3/4/5 pt radii become `sm`; 10 pt card radii become `lg`.

## Elevation & Depth

Depth is native and quiet.

- Windows sit in the normal window-server order. The pet panel and the permission guide may float because their function requires it; they do not use decorative shadows.
- Cards are **tonal surfaces** (`controlBackgroundColor`) with a 1 px `separatorColor` border. They do not use drop shadows.
- The frame editor's canvas uses a dimmed surround (`controlBackgroundColor` at 0.7) and a 1 px border to separate the sheet from the workspace. Guides are 1–2 px lines; they are not UI chrome and do not need the radius scale.
- Native alerts and sheets provide their own elevation. Do not build a custom modal layer.
- Focus rings are native and must not be removed. A custom control that cannot draw a native focus ring must draw an equivalent visible ring.

## Shapes

The shape language is **soft native**: 6 pt controls, 12 pt cards, 16 pt preview.

| Token | Value | Use |
| --- | --- | --- |
| `sm` | 6 | Buttons, small controls, status pills |
| `md` | 8 | Small surfaces, inner preview tiles |
| `lg` | 12 | Cards, option cards, drop zones, editor panels |
| `preview` | 16 | Setup preview stage |
| `full` | 9999 | X brand pill; circular movie play button |

- Do not introduce 3, 4, 5, 7, 10, 11, or 18 pt radii. The Frame Editor's 3/4/5 controls become 6; its 10 pt cards become 12; the Share card's 11 and inner 7 become 12 and 8.
- Brand X is the only pill-shaped action. The movie play overlay is the only circular control.
- Native controls keep their system shape. Do not override a bezel's radius.

## Components

### Actions

| Variant | Height | Type | Fill | Use |
| --- | --- | --- | --- | --- |
| Primary | 36 | `action` 13/500 | Accent, white label | The one most important action on the screen |
| Secondary | 36 | `action` 13/500 | Bordered/neutral | Alternative actions, Cancel, Back |
| Tertiary / link | 36 row | `action` 13/500 | None, accent label | "Change method", "Change image" |
| Destructive | 36 | `action` 13/500 | Red or red label | Discard, delete; always confirmed |
| Brand X | 36 | `action` 13/500 | X black/white pill | The single share action |
| Auxiliary | 28 | `caption`/`body` | Native small control | Zoom, stepper, segmented, canvas tools |

- Side padding is 12 pt; adjacent actions use `action-gap` 8. Apply the label padding via `actionLabel()` in Setup and Character Import, and via the same 36 pt intrinsic height in the Share button.
- A footer action is right-aligned; a secondary is left-aligned. The share action is centered because it is alone.
- Disabled actions keep their height and a readable label. Never rely on system disabled dimming for a brand button; the X button draws its own disabled content (see `PetShareActionButton.swift`).
- `.mini` and `.small` clickable controls are not allowed in new UI. The Frame Editor's existing mini/small controls migrate to `control-height` 28 or to a 36 pt action where they are real actions.

### Footer

A pinned footer is the default action area for setup-class windows:

- Full-width 1 px separator, `footer-inset` 12 above and below, a 36 pt row, content inset 24.
- Primary action at the trailing edge, secondary at the leading edge, 8 pt gap.
- The footer belongs to the window, not to the scrollable content. The content above must never hide it.
- Share uses the same footer geometry but centers its single brand action; the composer-failure status sits on the left and wraps to two lines.

### Cards and option cards

- Card: `controlBackgroundColor`, 1 px separator, radius 12, 16 pt internal padding, title `heading`, detail `caption`.
- Option card: 72 pt tall, radius 12, 1 px separator, icon 26 pt, title `heading`, detail `caption`, trailing chevron.
- Cards are not clickable unless the whole card is a button; when it is, use `.contentShape` and a visible hover/focus treatment.
- Do not nest cards more than one level deep.

### Status and inline errors

- Status = icon + text. Positive: check + `positive`; pending: circle + secondary; critical: triangle + `critical`.
- The label states the state in words ("Input Monitoring: allowed"), not just a color.
- Recoverable failures stay **inline** in the current step: caption size, critical color, one native accessibility announcement, previous state preserved.
- Use a native `NSAlert` only for destructive or blocking decisions (discard a draft, save failed, login item). Do not use a modal for a recoverable import/copy/browser failure.
- Never truncate instructions. The Share recovery text (#154) is the known counterexample and must be fixed by wrapping/reflow, not by ellipsis.

### Menus, alerts, and standard chrome

- Use native `NSMenu`, `NSMenuItem`, `NSAlert`, and standard window controls. Do not reimplement checkmarks, key equivalents, or alert buttons.
- Localize every menu title and button label; keep disabled commands discoverable with native help/subtitle reasons.
- Destructive alerts use a clear message, an informative body, a destructive confirmation, and Cancel.
- The main menu carries the standard Application, Edit, and Window commands; product commands live in the status menu and the pet context menu.

### Drag sources and drop zones

- The drag source is a visible app icon with an accessibility label and a manual fallback.
- Drop zones use `controlBackgroundColor` or an accent tint at 0.12, a 1.5 pt dashed separator outline, and radius 12. Hover increases the outline to accent; the preview and the file stay unchanged until the drop succeeds.
- Keep the drop target live across the relevant window; show the failure inline on the step where it happened.

### Frame editor controls

- Done and Reset are 36 pt actions in the title bar or a pinned footer. Pick one pattern per window; do not mix a 22 pt title-bar button with a 36 pt footer action.
- Zoom, numeric fields, steppers, and view toggles are 28 pt auxiliary controls with at least a 20 × 20 pt hit area.
- Crop handles may be visually 8–10 pt, but their hit area must be at least 20 × 20 pt.
- Canvas guides and the checkerboard are content: 1–2 px lines and the defined checkerboard values are allowed.
- Labels use `caption` 11 or `body` 13; there is no 9/10 pt text.

### X share action

- Official X glyph, template image, unmodified shape, 12 pt of clear space on the left inside the image so the pill edge cannot clip it.
- 36 pt pill, 13 pt label, black/white inversion between Light and Dark, fixed disabled pairs.
- Centered in the footer; no accent, no extra shadow, no custom hover color outside the neutral brand grays.
- The action is disabled (and readable) while assets are generating or failed; retry is the secondary action in the failure state.

## Do's and Don'ts

**Do**

- Use semantic NSColor/Color and native controls before custom drawing.
- Keep one primary action per screen; make it 36 pt and the default.
- Use the 4/8 pt scale, 24 pt content inset, 8 pt action gap, 12 pt footer inset.
- Use the type scale; 11 pt is the floor.
- Use the radius scale; 6 for controls, 12 for cards, 16 for the preview, `full` only for X/circular play.
- Pair every status with an icon and words; check 4.5:1 in Light and Dark.
- Respect Reduce Motion; replace movement with fades or no animation.
- Give every control an accessibility label, a keyboard path, and a visible focus ring.
- Keep imports, errors, and retries inline; preserve the previous state.
- Keep key codes ephemeral; keep images local.
- Localize both English and Japanese; test both in the fixed windows.

**Don't**

- Don't add a custom font, a new dependency, or a custom window chrome without a specific product reason.
- Don't use `Color.green`/`Color.red` for small text; use `positive`/`critical`.
- Don't use tertiary text for instructions or status.
- Don't use the accent color for the X brand action.
- Don't use color alone for state.
- Don't use `.mini`/`.small` for clickable controls.
- Don't use 3/4/5/7/10/11/18 pt radii or 9/10 pt text.
- Don't truncate recovery instructions.
- Don't let the Frame Editor become an exception; migrate it to the same tokens.
- Don't add a raw spacing/type/radius number to a view; add or use a token.

## Platform & Appearance

- **Platform:** macOS 14+, Apple Silicon, Swift 6, AppKit + SwiftUI, no third-party dependencies.
- **Appearance:** Light, Dark, and Increase Contrast. Use semantic colors; resolve `CGColor` per appearance. The pet art and the checkerboard are the only fixed-color surfaces.
- **Accent:** `controlAccentColor` is user-configurable. Use it for system actions and selection, never for the X brand.
- **Localization:** English and Japanese. Update `macos/en.lproj/Localizable.strings` and `macos/ja.lproj/Localizable.strings` together; run the localization generator.
- **Windows:** native title bars for setup-class windows; borderless only for the pet panel. Fixed windows are non-restorable. The permission guide may float beside System Settings.
- **Privacy:** no key codes outside the event tap; no logging/transmission; images stay on device; share assets are local until the user copies/posts.

## Accessibility

Apple's macOS baselines and Waddly's stricter values:

| Guideline | Apple macOS | Waddly |
| --- | --- | --- |
| Default text size | 13 pt | 13 pt (`body`) |
| Minimum text size | 10 pt | **11 pt** |
| Default control size | 28 × 28 pt | 28 pt auxiliary, 36 pt actions |
| Minimum control size | 20 × 20 pt | **20 × 20 pt** — never smaller; enlarge hit areas |
| Text contrast | 4.5:1 up to 17 pt; 3:1 at 18 pt/bold | **4.5:1 for all 11–13 pt text** |
| Larger text | Support enlargement (ideally 200%) | Prefer semantic text styles; fixed windows must reflow, not clip |
| Spacing | ~12 pt around bezeled controls, ~24 pt around bezel-less edges | `action-gap` 8; `section-gap` 16; 24 content inset |
| State | More than color | Icon + words + color |

**Required for every surface**

- Accessibility label and, where useful, hint. The label is the visible label; the hint explains the outcome, not the mechanics.
- Keyboard reachability: Tab/Shift-Tab reaches every action; Space/Return activates; Escape cancels; default action is Return.
- Visible focus ring. Do not rely on hover alone.
- One announcement per status transition or inline error; re-rendering must not repeat it.
- Reduce Motion: no scale/zoom/slide for essential feedback; use fades or immediate state changes.
- VoiceOver reading order matches the visual order; decorative images and icons are hidden.
- Test at larger text, Increase Contrast, Light/Dark, and both languages.

**Known gaps (track in the audit below):** fixed window sizes and fixed fonts vs. larger text; live VoiceOver and physical keyboard acceptance; the Frame Editor's 9/10 pt text and mini/small controls; #154 Japanese recovery-text truncation.

## Surfaces

| Surface | Host | Size | Layout | Type | Actions | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Setup Guide (Pet / Keyboard reactions / Ready) | SwiftUI in AppKit window | 820 × 520 fixed | `LayoutMetrics` 24/16/20/8/36/12 | display 25, body 13, caption 11 | 36 pt | ✅ layout/actions; 🟡 type literals |
| Character Import / Change Character | SwiftUI + AppKit preview | 1040 × 640 min | `LayoutMetrics` | title 15, body 13, caption 11 | 36 pt | ✅ |
| Frame Editor | SwiftUI + AppKit canvas | 1320 × 800 preferred, 1040 × 700 min | **migrating** to `LayoutMetrics`; keep geometry-only constants | **migrating** 9–14 → 11/13/15 | **migrating** mini/small → 28/36 | 🟡 must conform |
| Share | AppKit | 700 × 380 fixed | `LayoutMetrics` 24/36/8/12 | 13/11 | 36 pt + X brand pill | ✅ layout/actions; 🟡 #154 recovery text |
| Status menu / pet context menu / main menu | AppKit native | — | Native | Native | Native | ✅ |
| Pet panel | Borderless NSPanel | 180/240/320 square | Product-specific | — | Context menu | ⚪ deliberate no-chrome exception |
| Alerts and sheets | AppKit native | — | Native | Native | Native | ✅ |
| Permission guide | Setup shell beside System Settings | 820 × 520 | Setup tokens | Setup tokens | 36 pt | ✅; live QA pending |

Legend: ✅ conforms and is covered by code/tests; 🟡 known migration (the row names the conforming part and the gap); ⚪ intentional product exception. The Frame Editor is **not** an exception: its row is a migration, not a waiver.

## Guarantees & Gaps

**Guaranteed by code and tests**

- Setup, Character Import, and Share use the shared action height (36) and footer geometry; Share tests assert 36 pt actions, centering, and disabled fill brightness; the disabled content/fill contrast is a pending migration.
- Setup's four permission/readiness states and Share's working/failure/copy/composer states are covered by tests.
- Localization keys are checked by the generator; `mise run check` runs format, lint, complexity, safety, tests, and the signed build.
- Native menus, alerts, and windows inherit AppKit's HIG behavior.
- Reduce Motion is honored in setup transitions, pet reveal, and celebration.
- Share's X glyph, clear space, and disabled fill brightness have regression tests; the disabled content/fill contrast is a pending migration, covered by the Frame Editor follow-up.

**Not guaranteed yet**

| Gap | Impact | Target |
| --- | --- | --- |
| Frame Editor uses its own metrics, 9–14 pt type, mini/small controls, 3–10 pt radii | The densest surface is outside the system | Migrate to the shared tokens; see Migration |
| No type/radius/color token layer in code | New views can add one-off values | Extend `LayoutMetrics` (or a `DesignTokens` file) with the scales; review new literals |
| Setup/Character status text still uses system green/red | Small status text can fall below 4.5:1 | Use `positive`/`critical` and the Dark pairs |
| Auxiliary control rule not enforced | Mini controls can miss the 20 × 20 hit target | `.regular`/28 pt or padded hit area; no new mini/small |
| Large text / VoiceOver / Increase Contrast not automatically tested | Fixed layouts may clip; speech untested | Add a large-text layout test; manual VoiceOver/contrast pass |
| #154 Japanese recovery text truncates | Instructions become incomplete | Wrap/reflow; test at the default width |
| No `DESIGN.md` lint in CI | Token drift is possible | Optional `npx @google/design.md lint DESIGN.md`; do not add a Node dependency without a decision |

**Implementation contract**

| Token | Code |
| --- | --- |
| Content inset 24 | `LayoutMetrics.contentInset` |
| Section/column/action gaps 16/20/8 | `LayoutMetrics.sectionGap` / `columnGap` / `actionGap` |
| Action height 36 | `LayoutMetrics.actionHeight` + `actionLabel()`; `ShareActionButton` intrinsic height |
| Footer inset 12 | `LayoutMetrics.footerInset` |
| Preview width 360 | `LayoutMetrics.previewWidth` |
| Type scale | Target: a `DesignTokens` type layer; current Setup/Character/Share literals must match the table |
| Radius scale | Target: a `DesignTokens` radius layer; controls 6, cards 12, preview 16, brand X `full` |
| Status colors | Target: `positive`/`critical` tokens; current `Color.green`/`Color.red` text is a gap |

**Enforcement**

- Code review: a new raw spacing/type/radius/color value is a review finding; add or use a token.
- `mise run check` before merge.
- Snapshot tests (`CharacterImportSnapshotTests`, `ShareSnapshotTests`) for visual surfaces; add a Frame Editor snapshot after migration.
- Manual QA matrix for Light/Dark, EN/JA, larger text, Increase Contrast, Reduce Motion, VoiceOver, and real keyboard.

## Migration

**Frame Editor (must conform; highest priority)**

1. **Metrics:** keep the editor edge-to-edge. Replace `FrameEditorMetrics.outerPadding` with `lg` 16 for the title bar and panel padding, and use `sectionGap` between groups; use `contentInset` 24 only if a new surface needs a real window margin. Keep canvas geometry (sidebar 306, inspector 300/268, rail 58, breakpoint 1160, reserved heights) as named geometry constants, not as new spacing tokens.
2. **Type:** 9/10 → `caption` 11; 11 → `caption` 11; 13 → `body`/`heading` 13; 14 → `title` 15. No text below 11.
3. **Controls:** `.mini`/`.small` → `.regular` or a 28 pt auxiliary control with a ≥20 × 20 hit area. Done and Reset become 36 pt actions in either a 36 pt title-bar action row or a pinned footer; pick one and remove the other pattern.
4. **Radii:** 3/4/5 → `sm` 6; 8 → `md` 8; 10 → `lg` 12. Guides/checkerboard stay 1–2 px content.
5. **Colors:** replace `.green`/`.red` text with `positive`/`critical`; keep system fills for icons if they pass contrast. Use `warning` for the compose failure.
6. **Tests:** snapshot at 1040 × 700 and 1320 × 800, EN/JA, Light/Dark; keyboard/focus smoke; large-text layout.
7. **Documentation:** update the Surfaces table to ✅ and remove the Frame Editor from the gap list.

**Setup and Character Import**

- Replace the remaining ad-hoc 25/15/13/12/11 sizes with the type tokens (the values already match; make the dependency explicit).
- Replace `.green`/`.red` status text with `positive`/`critical`.
- Add a large-text/fixed-window layout test.

**Share**

- Keep the brand exception; migrate the calibrated disabled fills to the exact sRGB pairs and add the contrast assertion.
- Fix #154 by wrapping the recovery text and reflowing the status area; do not widen the window or ellipsize instructions.

**Global**

- Consider extracting a small `DesignTokens` layer next to `LayoutMetrics` for type, radius, and semantic status colors, so SwiftUI and AppKit share the same values.
- Add a PR checklist item: "Design tokens used; Light/Dark, EN/JA, keyboard, and Reduce Motion checked."

## References

- Apple HIG — [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Windows](https://developer.apple.com/design/human-interface-guidelines/windows).
- [Google Labs DESIGN.md format](https://github.com/google-labs-code/design.md) — the file structure and token schema used here.
- Code: `Sources/WaddlyApp/LayoutMetrics.swift`, `SetupWizardSwiftUIComponents.swift`, `CharacterImportView.swift`, `CharacterFrameEditor.swift`, `PetShareActionButton.swift`, `PetShareDialogView.swift`, `AppMainMenu.swift`.
