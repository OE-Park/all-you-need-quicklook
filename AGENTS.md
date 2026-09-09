# Agent contract

macOS QuickLook Preview Extension. Spec and plan live in `docs/superpowers/`.

## Working context

Before reviewing or editing, confirm the target worktree, branch, commit and dirty
files, then read that worktree's `AGENTS.md` and applicable `.github/` instructions.
A status note from another branch is not the target branch's implementation state.
Check task-relevant claims against source and recorded validation evidence.

## Build (Mac only)

```bash
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

`*.xcodeproj` is gitignored. Always regenerate.

## Validation scope

- Design/document-only review: building is optional. Existing green tests do not
  validate unimplemented behavior. State what was inspected and what was not run.
- Implementation changes: follow the assigned plan's TDD steps and run relevant
  tests plus the host-app build on macOS; cloud agents rely on CI for compilation.
- Rendering changes: exercise the affected behavior in a live `WKWebView` and
  verify the affected preview in Finder with Space. The host Preview tab and
  `qlmanage -p` do not prove extension registration or Finder routing.
- Test success is evidence only for the assertions executed. Report compilation,
  DOM assertions, visual checks and Finder checks separately, including pending
  manual checks. Do not mark verification complete while a required check remains.

## Status

Continuation starts at [HANDOFF.md](docs/superpowers/HANDOFF.md), which records
the current checkpoint, next task, verification scope and cross-service prompt.

Current scope: bounded pattern compiler and metered matcher, bundled as static
resources and tested through JavaScriptCore. They are not connected to preview
rendering or Settings. The [handoff](docs/superpowers/HANDOFF.md) is the authority
for current validation, pending DOM/UI integration and the next task. Avoid
copying checkpoint hashes or test counts here; they become stale.

The host UI integration preserves main's timeout-controlled image proxy,
private bundled fonts, and escaping fixes alongside explicit nonce plumbing.
Finder Space checks for .md/.ipynb/.log passed on the host integration build;
its running extension path was verified and prior registrations restored.

Tasks 1–12 form the original baseline. Tasks 13–17 were implemented on
`feat/host-app-ui` and are included in this branch: the host app
shell, WelcomeView, SettingsView and PreviewView, plus two defect fixes in
already-merged code — the CSP that never applied, and markdown code fences that
were never highlighted.

Task 17 step 4 is done. The owner enabled the extension; `.md`, `.ipynb` and
`.log` render through it in Finder. It found two defects, both fixed here:
`QLSupportedContentTypes` sat at the top level of the extension's `Info.plist`
instead of inside `NSExtension > NSExtensionAttributes` (so the appex declared
no supported types at all), and `.log` needed its concrete `com.apple.log` type
declared rather than only the `public.plain-text` ancestor.

In the recorded Finder check, `.txt` fell back to the system preview: both this
extension and the built-in preview declared `public.plain-text`, and the system
preview was selected. The host Preview tab rendered `.txt` correctly.

Task 17 step 3's sub-item 4, the dark-mode toggle, remains the owner's to run.

PlugInKit ignores an unsigned bundle, so `scripts/adhoc-sign.sh` runs as a
post-build phase and ad-hoc signs the framework, then the appex (with its
entitlements), then the app. Do not try to move this back into Xcode's own
signing: the App Group entitlement makes the build system demand a provisioning
profile, which `codesign` itself does not. Note also that every launched build
location registers its own copy, so the System Settings list accumulates
duplicates; clear them with `lsregister -u <path>`.

The script also signs the helper dylibs in `Contents/MacOS`
(`<name>.debug.dylib`, `__preview.dylib`) before their bundle. On Apple Silicon
the linker ad-hoc signs those already; on an x86_64 runner it does not, and
`codesign` refuses to sign a bundle whose nested code is unsigned. That is why
CodeQL's build failed while the same build passed locally.

## Hard rules

- Spec over plan if they conflict.
- One plan task at a time. TDD as written.
- Escape untrusted plain text for its destination (HTML text, quoted attribute,
  JavaScript string or JSON). HTML escaping is not JavaScript escaping.
- Inline script data needs both destination-appropriate serialization and HTML
  script-boundary protection. Use the matching `ScriptEscaping` API where present;
  do not feed serialized JSON through a string-literal escaper as a substitute.
- Markdown raw HTML and notebook `text/html` output are intentionally rendered as
  markup. They are untrusted, are not sanitized by marked, and must remain under
  CSP and navigation restrictions; do not accidentally escape these supported paths.
- Only app-controlled scripts may receive the document nonce. Never stamp scripts
  supplied by a previewed file. Preserve the nonce/CSP contract where implemented;
  legacy plan snippets are not authority to weaken it.
- Read the original plan's Security Note before changing a renderer or CSP.
- Every app-controlled `<script>` must carry the same fresh document nonce passed
  to `PreviewWebView.loadHTML(_:resourcesURL:nonce:)`. Keep bundled JS/CSS inlined;
  do not restore external resource tags or widen CSP to make them load.
- Copilot cloud agent cannot run Xcode. CI on `macos-26` is the compiler.

Web Copilot details: `.github/copilot-instructions.md`.
