# AllYouNeedQuickLook — Copilot instructions

macOS 15+ QuickLook Preview Extension. Host app (SwiftUI) embeds the extension. Shared framework converts Markdown / plain text / Jupyter notebooks to HTML and shows them in WKWebView.

Read the target worktree's `AGENTS.md` first. Use this file as guidance, then verify
task-relevant claims against source and recorded checks; report contradictions.

## Constraints the cloud agent cannot violate

- Copilot cloud agent runs on Ubuntu. It **cannot** run `xcodebuild`, open Xcode, or load QuickLook. Do not try. macOS CI (`ci.yml` on `macos-26` / Xcode 26.6) is the build/test authority.
- Never commit `*.xcodeproj`, `DerivedData/`, or `build/`. The project is generated from `project.yml` via XcodeGen.
- Spec wins if a plan and a spec disagree.
- Follow `AGENTS.md` for destination-specific escaping, raw-HTML paths and app-only nonce assignment.
- Keep the CSP and the navigation gate in `PreviewWebView`.

## Implementation validation (on a Mac / in CI)

For design/document-only review, builds are optional. Follow `AGENTS.md` for the
distinct requirements of implementation, live rendering and Finder verification.

```bash
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

On Ubuntu, inspect source and update the assigned files. Report local compilation
and runtime checks as unrun; use actual CI results for compilation/test claims.

## Layout

| Path | Role |
|------|------|
| `project.yml` | XcodeGen spec. Source of truth for targets, UTTypes, entitlements. |
| `scripts/adhoc-sign.sh` | Post-build ad-hoc signing. Without it the extension does not register. |
| `Shared/` | Framework used by host + extension. Models, ConfigLoader, renderers, HTML template, `PreviewWebView`. |
| `QuickLookExtension/` | `QLPreviewingController` entry, routing by file type. |
| `AllYouNeedQuickLook/` | SwiftUI host: Welcome, Settings, Preview tabs. |
| `Tests/` | XCTest against `Shared`; use the current test report for counts. |
| `docs/superpowers/` | Design specs + implementation plans. |

## Status

See [AGENTS.md](../AGENTS.md#status) for current design work and remaining manual
verification. Keep progress in that section rather than duplicating completion
claims here.

In the recorded Finder checks, `.md`, `.ipynb` and `.log` used the extension; `.txt` used the system preview despite `public.plain-text` being declared. Declaring only that ancestor did not win `.log` routing in that environment; adding `com.apple.log` did. These observations do not establish a universal platform limitation. Keep `QLSupportedContentTypes` inside `NSExtension > NSExtensionAttributes`. New UTTypes and changing `.txt` routing are outside the render-time design scope.

## Conventions

- Swift 6, macOS 15 deployment, App Sandbox, App Group `group.com.yohanpark.AllYouNeedQuickLook`.
- Renderers implement `Renderer.render(content:config:fileExtension:nonce:) -> String` and wrap via `HTMLTemplate.wrap(body:rendererType:nonce:customCSS:)`.
- TDD as a plan writes it: failing test, implement, pass, commit that task only.
- Do not add SwiftPM, CocoaPods, or new targets unless a plan says so. marked, highlight.js and KaTeX are vendored under `Shared/Resources/`.

## Two things that were learned the hard way — do not undo them

**Bundled JS/CSS is inlined into the template on purpose.** `loadHTMLString(_:baseURL:)` gives the document an opaque origin with no read access to the `file://` baseURL, so `<script src>` and `<link rel=stylesheet>` cannot load — not with `script-src 'self'`, not with `file:`, not with `allowFileAccessFromFileURLs`, not with the CSP removed entirely. Inlining is the only form that loads. Do not "fix" the template by restoring external references, and do not widen the CSP believing it will help.

**`script-src` names a per-load nonce and nothing else.** Every app-controlled `<script>` a renderer or `HTMLTemplate` emits must carry the document's nonce; scripts supplied by previewed content must never receive it. The same nonce must reach `PreviewWebView.loadHTML(_:resourcesURL:nonce:)`. An unstamped script silently does not run. The CSP meta is injected by a user script that creates `head` and attaches it to the document *before* inserting the meta — at `.atDocumentStart` there is no `head` yet, and getting this wrong means the policy never exists at all, with no error anywhere.

## Reviewing

A green build and a green suite are not evidence that a preview renders. This project has twice shipped code that built, passed every test, passed every review, and was dead on arrival — caught only by running the real app. When reviewing, prefer findings you can state as a concrete failure, and distinguish what passing assertions establish from untested runtime behavior. Existing tests do not validate an unimplemented design.

Resource integration: bundled JS/CSS stay inline with explicit document nonces.
Remote images retain main's timeout-controlled `quicklook-image:` handler;
bundled fonts retain `quicklook-resource://bundle`. Do not restore externally
linked script tags or remove the image timeout while resolving future merges.
