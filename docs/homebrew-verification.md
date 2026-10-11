# Homebrew and DMG release verification

Run this checklist on an Apple Silicon Mac with the release version and its published DMG available. Record the macOS version, Homebrew version, Waddly version, and results; use a test Mac or a disposable Homebrew environment so uninstalling does not remove a user's existing installation.

## Fresh Homebrew install

- [ ] Confirm the stable cask in `nyatinte/waddly` points at the intended release and its SHA-256 matches the published DMG.
- [ ] Run `brew update` and `brew install --cask nyatinte/waddly/waddly`.
- [ ] Confirm the install completes, `brew list --cask waddly` reports the cask, and `Waddly.app` is in `/Applications`.
- [ ] Confirm the Homebrew postflight removes `com.apple.quarantine` from the installed app: `xattr -p com.apple.quarantine /Applications/Waddly.app` should report that the attribute does not exist.
- [ ] Launch Waddly and verify the initial setup appears and the app remains usable.

## Upgrade

- [ ] With an earlier stable Waddly cask version installed, run `brew update` then `brew upgrade --cask waddly`.
- [ ] Confirm the cask reports the new version (`brew info --cask waddly`), the app in `/Applications` is the new version, and launch succeeds.
- [ ] Confirm the upgrade preserves user settings and registered pet images.

## Uninstall

- [ ] Run `brew uninstall --cask waddly`.
- [ ] Confirm Homebrew no longer lists the cask (`brew list --cask waddly` should fail because it is uninstalled) and `/Applications/Waddly.app` is removed.
- [ ] Confirm user settings and imported images remain available for a future reinstall; Homebrew uninstall should remove the app, not user data.

## First launch from a quarantined DMG

- [ ] Download the published DMG in a browser (do not remove quarantine) and verify its published checksum, for example: `shasum -a 256 Waddly-<VERSION>-macos-arm64.dmg`.
- [ ] Confirm quarantine is present on the downloaded DMG with `xattr -p com.apple.quarantine Waddly-<VERSION>-macos-arm64.dmg`.
- [ ] Open the DMG, copy `Waddly.app` to `/Applications`, eject the DMG, and launch the copied app for the first time.
- [ ] Record the actual macOS first-launch behavior and any Gatekeeper warning. The cask postflight only applies to Homebrew installs; do not assume it removes quarantine from a manually installed app.
- [ ] If macOS blocks the app, verify the documented user-approved recovery path in Privacy & Security and record whether launch then succeeds. Do not disable Gatekeeper globally or remove quarantine with `xattr` as part of this test.

## Recording results

Record the completed checks (macOS and Homebrew versions, Waddly version, DMG checksum, and the outcome of each step) in issue #66 or the release E2E report. Keep #66 open until a release has verified these scenarios; this checklist by itself is not the verification.
