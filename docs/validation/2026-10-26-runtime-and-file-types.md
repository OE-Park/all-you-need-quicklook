# Runtime integration and file-type settings validation

Date: 2026-10-26 (Asia/Seoul). Worktree: the user-designated
`DevFolder/Workspace/yohanpark-dev/public_repos/all-you-need-quicklook`.
Branch `main`, base HEAD `3ee0570119ebd72c169140a6d4801b717e16f8cd`.
This report records validation of the working tree before the delivery commit. No production-app replacement was performed.

## Result and limits

The original host/extension stubs are connected to the renderer pipeline.
Settings now saves added extensions immediately, normalizes names, preserves
existing overrides and explains Finder eligibility. Both Settings and Welcome
open the current System Settings extensions pane, with visible manual steps.
This fixes the misleading implication that adding a preference dynamically
registers a Finder file type. System Settings enables an extension; it does not
add file types or select a guaranteed provider.

**Not fully verified:** Finder remote-image downloads fail in this environment.
They safely become placeholders. Neither green WKWebView tests nor a host HTTP
200 response establishes successful network access from a Finder extension.
The complete 81-file corpus was not individually inspected in both appearances;
this report lists the actual representative checks. Plotly first-preview timing
was not formally measured. Do not mark the full corpus/release gate complete.

## Source and preservation

- Runtime source/resources/tests reused from the same repository's fixed
  `7c75faf` in the separate DevTools checkout. This is source reuse, not a claim
  that its prior validation applies here.
- Original source and the untracked Notebook renderer/tests preserved in
  `build/before-runtime-integration-20261026` before integration.
- New work: `FileTypeSupport`, extension-management actions and UI feedback,
  `PreviewBuildIdentity`, randomized build harness, local project rules and docs.
- Existing brand source under `assets/` retained. The imported icon catalog uses
  that same project series.
- The original March spec's blanket claim that added extensions immediately
  inherit `public.plain-text` is superseded by the supplemental implementation
  plan and actual UTType tests. Bundled declarations explicitly include JSON,
  YAML and TOML. XML/CSV/movie-typed `.ts` remain outside the claim.
- Primary reference: [Apple Quick Look documentation](https://developer.apple.com/documentation/quicklook/).

## Automated checks

Environment: macOS 26.7.1 (25G241), arm64, Xcode 27.1 (27A9275).

```sh
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests \
  -destination 'platform=macOS' -derivedDataPath build/runtime-tests
./script/build_and_run.sh --build-only
```

- FileTypeSupport RED: compilation failed because the model did not exist;
  `build/file-type-red.log` contains the missing-symbol errors. That sandboxed
  xcodebuild also encountered service restrictions, so it is not an assertion
  failure or passing test run.
- Identity RED: missing `PreviewBuildIdentity`; `build/build-identity-red.log`.
- Final suite: **275 tests, 0 failures, TEST SUCCEEDED**;
  `build/runtime-tests-final.log`. Includes live WKWebView tests of bundled
  libraries, Markdown/notebook math and syntax, Plotly JSON/typed arrays,
  relative images, CSP/navigation, remote-request gating and timeout behavior.
- Host/embedded extension: **BUILD SUCCEEDED** for test copies `9c051eae` and
  final `2f543413`; deep/strict codesign verification passed in the harness.
  Logs: `build/isolated-build-final.log`, `build/isolated-build-reviewed.log`,
  per-run `build/test-runs/<suffix>/build.log`.
- Final source differs from the 275-test run only by host explanatory strings,
  documentation and evidence. The final host strings were compiled and exercised
  in `2f543413`; renderer/model behavior was unchanged.
- `git diff --check` passed. Generated `.xcodeproj` and build output are ignored.
- Early SwiftUI build failed when sandboxing blocked the compiler macro plugin;
  the same sources built outside the tool sandbox. No compiler behavior was
  bypassed in product code.

## Randomized copies and isolation

`script/build_and_run.sh` / `script/test_build.py` stage the working-tree sources,
list prior test apps, generate eight hexadecimal characters and build
`AllYouNeedQuickLook-<suffix>.app`. Host/extension/framework bundle IDs and the
config directory are unique. Config path and signed entitlement agree.

Final manifest: `build/test-runs/2f543413/manifest.json`.
Final app: `build/test-runs/2f543413/DerivedData/Build/Products/Debug/AllYouNeedQuickLook-2f543413.app`.
Final config: `~/Library/Application Support/AllYouNeedQuickLook-Test-2f543413/config.json`.

The first attempt used a nested missing parent directory and correctly produced
a Save permission error in the UI. The harness now uses a single-level config
folder, and both `9c051eae` and `2f543413` saved successfully.
Prior test bundles `803c942a`, `e865f879`, `9c051eae` were closed, unregistered
and removed after checking exact paths. Their source stages/logs remain.
No `/Applications` bundle or production config was deleted or replaced.

## Computer checks actually executed

All GUI actions used the computer tool. The source corpus was copied earlier to
`~/Projects/TEST_SAMPLES/all-you-need-quicklook/2026-10-26`; the 81 source-file
hashes were verified in that preparation session. This session used those
samples and a few explicitly named network/final-check probe copies.

| Check | Observed result / identity |
| --- | --- |
| Add `.YAML` | Normalized to `yaml`, saved immediately in `9c051eae`; disk JSON contains the key |
| Add `xml` | Saved formatting, displayed explicit Finder unsupported feedback |
| Final Add `yaml` | New isolated `2f543413` settings saved successfully; [screen](artifacts/2026-10-26/settings-final.png) |
| System Settings action | Arrived at General → Login Items & Extensions; test app details showed its Quick Look switch on |
| Host Preview | YAML coloured; notebook cells/math rendered; [YAML](artifacts/2026-10-26/host-yaml.png), [notebook](artifacts/2026-10-26/host-notebook.png) |
| Finder YAML | `basic.yaml` colours/gutter and `Test build 9c051eae`; [screen](artifacts/2026-10-26/finder-yaml.png) |
| Finder Markdown | Headings/list indentation/block spacing; light and dark; `9c051eae`; [light](artifacts/2026-10-26/finder-markdown.png), [dark](artifacts/2026-10-26/finder-markdown-dark.png) |
| Finder notebook | Cell formatting, code highlight and visible KaTeX; `9c051eae`; [screen](artifacts/2026-10-26/finder-notebook.png) |
| Finder log | INFO/DEBUG/WARN/ERROR/FATAL/CRITICAL colours; `9c051eae`; [screen](artifacts/2026-10-26/finder-log.png) |
| Finder Plotly | Plain-array and typed-array charts both visible; `9c051eae`; [screen](artifacts/2026-10-26/finder-plotly.png) |
| Finder relative images | Sibling/subfolder/parent/%20/SVG/query reference visible; fake PNG refused; light/dark; [light](artifacts/2026-10-26/finder-local-images.png), [dark](artifacts/2026-10-26/finder-local-images-dark.png) |
| Remote images off | Explicit blocked placeholder in Finder; `9c051eae`; [screen](artifacts/2026-10-26/finder-remote-off.png) |
| Remote images on + Save + reopen | Changed to unavailable placeholder; download FAILED; see below |
| Corrupt config | In `2f543413`, exact “Settings could not be read; using defaults.” plus test identity and content; [screen](artifacts/2026-10-26/finder-corrupt-settings-final.png) |
| Final JSON | Coloured JSON with `Test build 2f543413`; [screen](artifacts/2026-10-26/finder-json-final.png) |

No repeated data-access consent dialog appeared during the executed first-load
and post-save checks. This observation covers these copies and this session,
not all macOS signing/distribution configurations.

For final routing, Finder initially selected the existing `/Applications`
provider even though the test provider was enabled. Screens without a test
identity were not credited to this source. The existing provider's recorded
state was `use`; it was temporarily set to `ignore`, final tests executed,
and restored to `use` afterward. Test config corruption was restored
byte-for-byte. The original system appearance was Light, temporarily changed to
Dark for checks, then restored to Light.

## Remote-network failure: unresolved

- The public Apple favicon URL returned HTTP 200 via terminal curl.
- A temporary loopback server serving one known PNG received no request during
  the Finder preview. A terminal control GET reached it and returned HTTP 200.
  The server was stopped afterward.
- The test extension had `network.client`; image policy was on and replaced the
  blocked message with the unavailable message. This proves settings propagation
  and failure handling, not success of WebKit networking in the Finder sandbox.
- Narrow process/log inspection confirmed invocation of the test appex. WebKit
  logged sandbox/service failures; no specific single cause was established.
- The older vault note's success came from a different spike/entry path; do not
  generalize either observation to a universal platform capability or limit.
- Next investigation: minimal real-Finder reproducer comparing nil vs file base
  URL and network-process behavior, without weakening CSP or adding speculative
  sandbox exceptions. No Swift downloader or helper daemon was added.

## Review and remaining checks

A separate read-only reviewer found no blocking P1/P2 issue in the new support
model, settings action, test identity or build isolation boundaries. Its minor
wording suggestion was applied. It did not perform a full security audit or
replace the computer checks above.

Remaining: resolve real-Finder remote-image networking; full corpus in both
appearances; formal first-preview performance timing; signed/notarized release
validation. These are explicitly not marked complete. The retained final test extension was set to `ignore` after validation to avoid competing with the restored production provider; its app remains available for review. Commit and PR delivery are recorded separately in the daily session.

## PR delivery validation

The delivery branch was rebased onto `origin/main` at
`8cafa6d81e28636e39d297c0174b7b5edeeb2966`. Existing remote changes and
security guidance were preserved; obsolete Swift image transport/tests were
removed in favor of the already-validated WebKit path. Installation/corpus
scripts were reconciled with the new config location and cases.

- Full suite rerun after reconciliation: **275 tests, 0 failures, TEST SUCCEEDED**
  (`build/pr-rebased-tests.log`).
- Fresh randomized build `dd38b75d`: **BUILD SUCCEEDED**, deep/strict signature
  verification passed (`build/pr-rebased-build.log`). It was not launched.
- Runtime/model/rendering/test contents match the previous validated snapshot;
  only obsolete empty `.gitkeep` files differ in those source directories.
- The previous computer/Finder evidence remains attributed to the explicitly
  recorded test copies. No new Finder or remote-network success is inferred.
