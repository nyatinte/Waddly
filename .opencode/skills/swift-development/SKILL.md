---
name: Swift Development
description: Apply Swift 6, AppKit, concurrency-safety, API-design, and quality practices when writing or reviewing this project's Swift code.
---

# Swift Development

Adapted for this repository from [sammcj/agentic-coding's Swift development skill](https://github.com/sammcj/agentic-coding/tree/main/Skills/swift-development). Licensed under Apache-2.0; see `LICENSE`.

## Project constraints

- The app targets macOS 13 and uses Swift 6, AppKit, Core Graphics, and Core Animation. Check API availability against macOS 13 before using newer platform APIs.
- Keep runtime dependencies at zero. Use the existing frameworks and patterns before proposing a package.
- Keyboard events are listen-only. Inspect the Enter key code transiently; never store, log, or transmit key codes or typed content.
- Imported images and their processing stay on the device.

## Working rules

- Use `@MainActor` for AppKit objects and UI state. Keep shared mutable state isolated; add `Sendable` only when the compiler or API contract requires it.
- Prefer synchronous code for synchronous work. When adding asynchronous work, check cancellation in long-running operations and do not assume `async` means background execution.
- Handle optionals and errors at their source. Prefer guards and explicit fallbacks to force unwraps, forced casts, or `try!`.
- Keep APIs clear at their call sites, use role-based names, and document declarations only when they form a public API or need non-obvious rationale.
- Keep functions and types focused. Extract cohesive responsibilities instead of suppressing SwiftLint size or complexity rules.
- Preserve the macOS 13 deployment target and existing privacy behavior when refactoring.

## Verification

Run `swift test` for the Swift Testing suites. Run `./macos/build.sh` after Swift changes; it checks SwiftFormat, enforces `.swiftlint.yml` with `swiftlint lint --strict`, and builds the Release app.
