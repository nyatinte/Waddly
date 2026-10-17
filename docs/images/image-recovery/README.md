# Unreadable-image-list alert renders

Native NSAlert content-view renders from `d2adc00`, English (`2`) / Japanese (`1`), light / dark. The capture harness invokes the real `AppDelegate.showImageSaveError(PetImageManifestError.unreadable)` path with an Animation Settings parent and isolated temporary preferences/sample images. It supplies the error directly; these images do not assert that a corrupt production manifest was reproduced manually.

`cacheDisplay(in:to:)` captures the content, composited over `NSColor.windowBackgroundColor` because a native sheet's background is transparent. This is not a screen capture, and does not reproduce vibrancy, window chrome, app icon, or the surrounding parent window. No user pet or preferences were read or changed. English/light and Japanese/dark content were inspected for readable copy and clipping; the other pair is included for comparison. Keyboard focus and actual VoiceOver speech were not checked.
