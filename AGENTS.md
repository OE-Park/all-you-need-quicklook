# Agent contract

macOS QuickLook Preview Extension. Spec and plan live in `docs/superpowers/`.

## Build (Mac only)

```bash
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

`*.xcodeproj` is gitignored. Always regenerate.

## Status

Plan tasks 1–11 are on `main`. Next is Task 12 `PreviewViewController`.

## Hard rules

- Spec over plan if they conflict.
- One plan task at a time. TDD as written.
- Escape user content before HTML injection.
- Copilot cloud agent cannot run Xcode. CI on `macos-26` is the compiler.

Web Copilot details: `.github/copilot-instructions.md`.
