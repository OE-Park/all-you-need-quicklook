# AllYouNeedQuickLook — Copilot instructions

macOS 15+ QuickLook Preview Extension. Host app (SwiftUI) embeds the extension. Shared framework converts Markdown / plain text / Jupyter notebooks to HTML and shows them in WKWebView.

Trust this file. Search the repo only when something here is missing or wrong.

## Constraints the cloud agent cannot violate

- Copilot cloud agent runs on Ubuntu. It **cannot** run `xcodebuild`, open Xcode, or load QuickLook. Do not try. macOS CI (`ci.yml` on `macos-26` / Xcode 26.6) is the build/test authority.
- Never commit `*.xcodeproj`, `DerivedData/`, or `build/`. The project is generated from `project.yml` via XcodeGen.
- Follow `docs/superpowers/plans/2026-03-30-quicklook-extension.md` task order. Do not skip ahead or invent extra file types.
- Spec is `docs/superpowers/specs/2026-03-30-quicklook-extension-design.md`. Spec wins if the plan and spec disagree.
- HTML from user content must be escaped on the Swift side before injection. Keep CSP + navigation blocking in PreviewWebView.

## Always do this to validate (on a Mac / in CI)

```bash
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

On Ubuntu (this agent): edit Swift/YAML, keep tests compiling in your head, leave CI to fail the PR if the build is wrong.

## Layout

| Path | Role |
|------|------|
| `project.yml` | XcodeGen spec. Source of truth for targets, UTTypes, entitlements. |
| `Shared/` | Framework used by host + extension. Models, ConfigLoader, renderers, HTML template. |
| `QuickLookExtension/` | `QLPreviewingController` entry. Still a stub until Task 12. |
| `AllYouNeedQuickLook/` | SwiftUI host. `App.swift` is still a placeholder until Tasks 13–16. |
| `Tests/` | XCTest against `Shared`. |
| `docs/superpowers/` | Design spec + implementation plan (Tasks 1–17). Tasks 1–8 are done. |

Next unfinished plan task: **Task 9 `NotebookRenderer`**.

## Conventions

- Swift 6, macOS 15 deployment, App Sandbox, App Group `group.com.yohanpark.AllYouNeedQuickLook`.
- Renderers implement `Renderer.render(content:config:fileExtension:) -> String` and wrap via `HTMLTemplate.wrap`.
- TDD as the plan writes it: failing test, implement, pass, commit that task only.
- Do not add SwiftPM, CocoaPods, or new targets unless the plan says so. JS libraries (marked, highlight.js, KaTeX) are vendored in Task 11.
- PreviewWebView CSP as first written (`script-src 'unsafe-inline'` only) will block `<script src>` / `<link>` in `HTMLTemplate`. When implementing Task 10, allow `'self'` (or equivalent) so bundled JS/CSS/fonts load.
- Resource `baseURL` must be the Shared bundle (`Bundle(for: ConfigLoader.self)`), not the extension or host bundle.
