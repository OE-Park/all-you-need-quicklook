# AllYouNeedQuickLook — Copilot instructions

macOS 15+ QuickLook Preview Extension. Host app (SwiftUI) embeds the extension. Shared framework converts Markdown / plain text / Jupyter notebooks to HTML and shows them in WKWebView.

Trust this file. Search the repo only when something here is missing or wrong.

## Constraints the cloud agent cannot violate

- Copilot cloud agent runs on Ubuntu. It **cannot** run `xcodebuild`, open Xcode, or load QuickLook. Do not try. macOS CI (`ci.yml` on `macos-26` / Xcode 26.6) is the build/test authority.
- Never commit `*.xcodeproj`, `DerivedData/`, or `build/`. The project is generated from `project.yml` via XcodeGen.
- Spec wins if a plan and a spec disagree.
- HTML from user content must be escaped on the Swift side before injection. Anything reaching an inline `<script>` goes through `ScriptEscaping` first.
- Keep the CSP and the navigation gate in `PreviewWebView`.

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
| `scripts/adhoc-sign.sh` | Post-build ad-hoc signing. Without it the extension does not register. |
| `Shared/` | Framework used by host + extension. Models, ConfigLoader, renderers, HTML template, `PreviewWebView`. |
| `QuickLookExtension/` | `QLPreviewingController` entry, routing by file type. |
| `AllYouNeedQuickLook/` | SwiftUI host: Welcome, Settings, Preview tabs. |
| `Tests/` | XCTest against `Shared`. 107 tests. |
| `docs/superpowers/` | Design specs + implementation plans. |

## Status

The original plan (`docs/superpowers/plans/2026-03-30-quicklook-extension.md`, Tasks 1–17) is **complete** and verified end to end in Finder. Current work is the render-time features spec, `docs/superpowers/specs/2026-09-06-render-time-features-design.md`.

`.md`, `.ipynb` and `.log` render through the extension. `.txt` does not and cannot: its type *is* `public.plain-text`, which the built-in text preview also declares and wins. Do not try to fix that by declaring an ancestor type — parent-UTI matching is not supported, and `QLSupportedContentTypes` must sit inside `NSExtension > NSExtensionAttributes` or QuickLook ignores it silently.

## Conventions

- Swift 6, macOS 15 deployment, App Sandbox, App Group `group.com.yohanpark.AllYouNeedQuickLook`.
- Renderers implement `Renderer.render(content:config:fileExtension:nonce:) -> String` and wrap via `HTMLTemplate.wrap(body:rendererType:nonce:customCSS:)`.
- TDD as a plan writes it: failing test, implement, pass, commit that task only.
- Do not add SwiftPM, CocoaPods, or new targets unless a plan says so. marked, highlight.js and KaTeX are vendored under `Shared/Resources/`.

## Two things that were learned the hard way — do not undo them

**Bundled JS/CSS is inlined into the template on purpose.** `loadHTMLString(_:baseURL:)` gives the document an opaque origin with no read access to the `file://` baseURL, so `<script src>` and `<link rel=stylesheet>` cannot load — not with `script-src 'self'`, not with `file:`, not with `allowFileAccessFromFileURLs`, not with the CSP removed entirely. Inlining is the only form that loads. Do not "fix" the template by restoring external references, and do not widen the CSP believing it will help.

**`script-src` names a per-load nonce and nothing else.** Every `<script>` a renderer or `HTMLTemplate` emits must carry the document's nonce, and that same nonce must reach `PreviewWebView.loadHTML(_:resourcesURL:nonce:)`. An unstamped script silently does not run. The CSP meta is injected by a user script that creates `head` and attaches it to the document *before* inserting the meta — at `.atDocumentStart` there is no `head` yet, and getting this wrong means the policy never exists at all, with no error anywhere.

## Reviewing

A green build and a green suite are not evidence that a preview renders. This project has twice shipped code that built, passed every test, passed every review, and was dead on arrival — caught only by running the real app. When reviewing, prefer findings you can state as a concrete failure, and treat "the tests pass" as no evidence at all.
