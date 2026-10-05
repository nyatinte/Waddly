[Issue #45](https://github.com/nyatinte/Waddly/issues/45)

## Why the change

Localization previously read language preferences from the global settings singleton, so injected settings could not control displayed strings; this change makes the injected settings the source of truth.

## Special things to note

- Runtime language refresh and fallback behavior from the base branch are preserved; this change injects their settings source.

## Change outline

Settings now flow through one controller to each localized UI surface:

```text
AppDelegate(settings)
  └── LocalizationController(settings)
      ├── menu strings and selected language
      ├── setup wizard strings and prompt
      └── image settings, category labels, and accessibility text
```

```text
Sources/WaddlyApp/
├── AppModels.swift             # injected language resolution and string lookup
├── Waddly.swift                # AppDelegate owns the controller
├── AppDelegateMenu.swift       # menu reads and changes injected language
├── PetImageSettings.swift      # passes controller into image settings
├── PetImageViews.swift         # localized labels and accessibility names
├── SetupWizard.swift           # localized setup UI
├── SetupWizardPrompt.swift     # prompt language selection
└── SetupWizardViews.swift      # passes controller to setup subviews
```
