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

Task 17 step 4 is done. The owner enabled the extension; `.md`, `.ipynb` and
`.log` render through it in Finder. It found two defects, both fixed here:
`QLSupportedContentTypes` sat at the top level of the extension's `Info.plist`
instead of inside `NSExtension > NSExtensionAttributes` (so the appex declared
no supported types at all), and `.log` needed its concrete `com.apple.log` type
declared rather than only the `public.plain-text` ancestor.

`.txt` still falls back to the system preview: its type *is* `public.plain-text`,
which the built-in text preview also declares and wins. The Preview tab renders
`.txt` correctly; the extension does not.

Task 17 step 3's sub-item 4, the dark-mode toggle, remains the owner's to run.

PlugInKit ignores an unsigned bundle, so `scripts/adhoc-sign.sh` runs as a
post-build phase and ad-hoc signs the framework, then the appex (with its
entitlements), then the app. Do not try to move this back into Xcode's own
signing: the App Group entitlement makes the build system demand a provisioning
profile, which `codesign` itself does not. Note also that every launched build
location registers its own copy, so the System Settings list accumulates
duplicates; clear them with `lsregister -u <path>`.

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
