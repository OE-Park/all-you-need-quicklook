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
```

The Xcode project is generated and gitignored. Edit `project.yml`, not `.xcodeproj`.

## Status

Implementation plan: `docs/superpowers/plans/2026-03-30-quicklook-extension.md`  
Design spec: `docs/superpowers/specs/2026-03-30-quicklook-extension-design.md`

Tasks 1–8 are on `main`. Next is Task 9 (`NotebookRenderer`).

## Agent / Copilot

See `AGENTS.md` and `.github/copilot-instructions.md`.
