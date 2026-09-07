# All You Need QuickLook

macOS QuickLook Preview Extension for Markdown, plain text/logs, and Jupyter notebooks.

## Requirements

- macOS 15+
- Xcode 26.6 (CI uses `macos-26`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build and test

```bash
brew install xcodegen   # once
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

The Xcode project is generated and gitignored. Edit `project.yml`, not `.xcodeproj`. The app and extension use automatic signing with the configured development team; CI disables signing explicitly.

## Status

Implementation plan: `docs/superpowers/plans/2026-03-30-quicklook-extension.md`  
Design spec: `docs/superpowers/specs/2026-03-30-quicklook-extension-design.md`

Tasks 1–12 are on `main`. The rendering pipeline has runtime coverage for bundled libraries, CSP, navigation blocking, and external-image failure handling. Next is Task 13 (`Host App UI`).

## Agent / Copilot

See `AGENTS.md` and `.github/copilot-instructions.md`.
