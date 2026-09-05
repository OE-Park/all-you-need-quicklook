# Agent contract

macOS QuickLook Preview Extension. Spec and plan live in `docs/superpowers/`.

## Build (Mac only)

```bash
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

`*.xcodeproj` is gitignored. Always regenerate.

## Status

Tasks 1–12 are on `main`. Tasks 13–17 are on `feat/host-app-ui`: the host app
shell, WelcomeView, SettingsView and PreviewView, plus two defect fixes in
already-merged code — the CSP that never applied, and markdown code fences that
were never highlighted.

Task 17 is not finished. Step 3's manual checklist is done except sub-item 4,
the dark-mode toggle, which changes a system setting and is therefore the
owner's to run.

Task 17 step 4 (enable the extension in System Settings, press Space in Finder)
is **deferred to the repository owner**: it changes system settings, so agents do
not perform it. It is the only cover `PreviewViewController`,
`QLSupportedContentTypes` and the `org.jupyter.notebook` UTType have.

## Hard rules

- Spec over plan if they conflict.
- One plan task at a time. TDD as written.
- Escape user content before HTML injection, and through `ScriptEscaping` before
  any injection into an inline `<script>`. The plan's Security Note is the threat
  model; read it before touching a renderer or the CSP.
- Every `<script>` a renderer or `HTMLTemplate` emits must carry the document's
  nonce, and that same nonce must reach
  `PreviewWebView.loadHTML(_:resourcesURL:nonce:)`. `script-src` names the nonce
  and nothing else, so an unstamped script silently does not run.
- Copilot cloud agent cannot run Xcode. CI on `macos-26` is the compiler.

Web Copilot details: `.github/copilot-instructions.md`.
