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

## Installing for a Finder check

Every build location that is *launched* registers its own Quick Look
extension, and the record outlives the directory. A worktree built under
`/private/tmp` leaves a ghost in System Settings long after the directory is
gone, and with several of them there is no way to tell which copy Finder
actually invoked — the duplicate rows are indistinguishable.

So a Finder check is run against one installed copy at a known path, never
against a build product in place:

```bash
scripts/install-to-applications.sh [--reset-config] [--keep-derived-data]
```

It quits the running copy, builds Release, unregisters **every** recorded
path (ghosts included), installs to `/Applications`, verifies the signature,
prints the appex's `QLSupportedContentTypes`, removes the built copies from
DerivedData and restarts `quicklookd`. `--reset-config` deletes
`~/Library/Application Support/AllYouNeedQuickLook/config.json`, which is the reset: `ConfigLoader.load()` falls back to the
bundled `default-config.json` while no file exists.

Launching the app once afterwards is still manual — the system only offers
the extension after that — as is enabling it in System Settings.

Do not report a Finder result without saying which copy produced it.

## Preview verification corpus

Any change to a renderer, to `HTMLTemplate`, to the escaping helpers, to
`SyntaxLanguageMap` or to `QLSupportedContentTypes` is verified against the
corpus, not against ad-hoc samples invented for the occasion.

```bash
python3 scripts/make-preview-corpus.py          # -> ~/Desktop/AYNQL-test
python3 scripts/make-preview-corpus.py <dir>    # or somewhere else
```

The destination is wiped and rebuilt. Read `000-CHECKLIST.md` in it first: it
states what each directory proves and what the correct outcome looks like,
including the cases where the correct outcome is *no* preview from this
extension.

The corpus is generated rather than committed. The generator is the authority
on why each file exists, so add cases there rather than dropping files into
the destination — anything added by hand is lost on the next run. New escaping
hazards, new size bounds and newly claimed content types each earn a case.

What it covers, and what each directory is for:

| Directory | Proves |
|---|---|
| `01-newly-routed` | `public.json` / `public.yaml` / `public.toml` reach the extension at all |
| `02-markdown` | block spacing, fence highlighting, the unsupported-language label |
| `03-special-chars` | `HTMLEscaper`, both `ScriptEscaping` forms, `CSSStringEscaper`, the ISO-8859-1 fallback, line endings |
| `04-size-limits` | `boundedPreview` on both bounds, either side of each |
| `05-regression` | log level patterns, plain `.txt`, notebooks |
| `06-source-code` | extension-driven language resolution |
| `12-expanded-source` | suffix-by-suffix routing fixtures and UTF-16 PowerShell |
| `07-not-claimed` | types deliberately left to the system preview |
| `08-malformed` | graceful failure |
| `11-sandbox-realities` | relative images (including `../`, `%20`, SVG and a refused fake), remote images off/on, Plotly figures, pandas HTML, HTML-only Plotly |

Rendering it is not the same as checking it. The corpus only pays for itself
when previewed with Space in Finder, in **both** appearances — several cases
(blockquote contrast, theme switching) are invisible in one of them.

## Status

The source/script expansion checkpoint is in `PROJECT_STATUS.md` and
`docs/validation/2026-10-27-source-formats.md`; the format list is
`docs/SOURCE_FORMATS.md`. Native System Settings owns activation. The host's
processed Info.plist is an explicit input to its ad-hoc signing phase.
The historical baseline below does not supersede that checkpoint.


Continuation starts at [HANDOFF.md](docs/superpowers/HANDOFF.md), which records
the current checkpoint, next task, verification scope and cross-service prompt.

The bounded pattern compiler and metered matcher are now used by plain-text log
rendering through JavaScriptCore. Markdown/notebook DOM pattern highlighting and
Settings pattern validation remain future work. The [handoff](docs/superpowers/HANDOFF.md)
links the authority for current implementation and validation. Avoid copying
checkpoint hashes or test counts here; they become stale.

The host UI integration keeps remote images quarantined until the 25 MiB response cap can be enforced
(CSP blocks HTTP(S) even for legacy opt-in settings; no unbounded transport), private bundled fonts, and escaping fixes alongside explicit nonce plumbing.
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
signing. The App Group is gone (a `group.` identifier under ad-hoc signing makes
macOS prompt on every preview; settings now live in Application Support), but
re-enabling Xcode signing is out of scope. Note also that every launched build
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
  to `PreviewWebView.loadHTML(_:resourcesURL:nonce:notice:documentDirectory:)`. Keep bundled JS/CSS inlined;
  do not restore external resource tags or widen CSP to make them load.
- Copilot cloud agent cannot run Xcode. CI on `macos-26` is the compiler.

Web Copilot details: `.github/copilot-instructions.md`.


## User-designated checkout and isolated testing

# QuickLook project instructions

Work in this user-designated DevFolder checkout. A second DevTools checkout of
the same repository is separate state. Confirm branch, HEAD and dirty files.

- Generate the ignored Xcode project from `project.yml` with XcodeGen.
- Run the Tests scheme on macOS and build the host/embedded extension.
- Preserve per-document nonces, inline vendored JS/CSS, CSP and navigation policy.
- Only app-controlled scripts receive the document nonce.
- Settings changes formatting, not the bundled `QLSupportedContentTypes` list.
  System Settings enables extensions; it cannot dynamically register file types.
- Before UI testing, inspect existing test copies. New test apps use
  `AllYouNeedQuickLook-<random alphanumeric>.app`; isolate bundle identifiers and
  settings paths too. `script/build_and_run.sh --build-only` implements this.
- Old test copies may be removed after checking their exact paths and closing
  them. Never reset production settings or unregister unrelated installed apps.
- Use the user's shared samples under `~/Projects/TEST_SAMPLES/all-you-need-quicklook`.
- Separate compilation, unit/string assertions, live WKWebView, visual and Finder
  results. A successful host preview does not establish Finder routing. Random
  test builds identify themselves in Finder with `Test build <suffix>`.
- Remote images are now deliberately blocked until an enforceable 25 MiB
  response cap exists. Legacy opt-in values cannot bypass CSP. Embedded/local
  images remain supported; do not restore unbounded network transport.
- The current status authority is `PROJECT_STATUS.md`; review/clean-install evidence is
  `docs/validation/2026-10-26-pr-review-clean-install.md`.
  Keep pending checks explicit. Projects daily-note rules still apply.
