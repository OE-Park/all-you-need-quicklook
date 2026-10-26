# All You Need QuickLook

A macOS 15+ SwiftUI app and Finder Quick Look extension for Markdown, logs,
source/text files, JSON/YAML/TOML and Jupyter notebooks. Shared renderers use
bundled marked, highlight.js, KaTeX and Plotly inside a restricted WKWebView.

## Project status

See [PROJECT_STATUS.md](PROJECT_STATUS.md) for the active checkout, branch/PR,
implementation status, verification results, sample/build locations and next work.

## Development

Requires Xcode, XcodeGen and Python 3.

```sh
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS'
./script/build_and_run.sh
```

The Run action builds a fresh `AllYouNeedQuickLook-<random>.app`, using unique
host/extension/framework identifiers and a matching isolated settings directory.
It lists prior test apps and preserves them for inspection. Use `--build-only`
to build without launching, then open the returned absolute app path for a
computer-tool verification. Inspect `build/test-runs/latest.json` for exact paths.
The normal project uses `~/Library/Application Support/AllYouNeedQuickLook`;
test copies use `~/Library/Application Support/AllYouNeedQuickLook-Test-<random>`.
No production app, settings, or global Quick Look registration is reset.

## File type settings and Finder

Adding an extension saves its formatting immediately; other edits use Save.
Leading dots, case and whitespace are normalized. Adding an existing extension
preserves its settings. Preview refreshes after a successful save.

Formatting preferences do not dynamically register Finder types. Finder invokes
eligible extensions based on `NSExtension > NSExtensionAttributes >
QLSupportedContentTypes` in their bundled Info.plist. JSON, YAML and TOML are
explicitly declared because they do not inherit `public.plain-text`.
Settings reports declared, unsupported and unknown types from the bundled appex.

Use **Manage Quick Look in System Settings** to open **General → Login Items &
Extensions**. Open this app's details and enable **Quick Look** (훑어보기).
This enables the extension; it does not add file types or guarantee which
provider macOS chooses when several qualify. XML, CSV and movie-typed `.ts`
files are left to macOS. Text routing can also use the system provider.

Remote images are unavailable in this version: direct WebKit image loading does
not expose an enforceable 25 MiB response cap. CSP refuses HTTP(S) images even
for imported legacy opt-in settings. Embedded and validated local images remain
available; responsive/lazy remote candidates receive a blocked placeholder.
The disabled Settings controls make this limitation visible.

Use **Import Settings JSON…** to explicitly restore a readable previous config,
including an exported App Group config. Import validates JSON before replacing
current settings. No automatic migration runs, so a clean reset cannot revive
old settings. Add saves only the extension; unrelated form edits still need Save.

## Current evidence

See [the validation report](docs/validation/2026-10-26-runtime-and-file-types.md)
for executed tests, computer checks, exact test-copy identity and pending checks.
Source integration reused this repository's runtime from commit `7c75faf` in the
separate DevTools checkout; validation here was rerun against this working tree.
The initial DevFolder files, including the untracked Notebook renderer/tests,
are preserved under `build/before-runtime-integration-20261026`.
