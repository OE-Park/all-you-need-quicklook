# Metered NFA feasibility experiment

**Throwaway research code, not a production implementation.** `probe.js` compiles
manually supplied ASTs for a small subset. It is not a user-regex parser, a complete
matcher or the full document-budget implementation. It is not included in any
Xcode target. Do not move it into Shared as-is.

## Observed results — 2026-09-07

macOS 26.6.2, Xcode 26.6, arm64. Compiled the temporary Swift runner against the
previously built baseline Shared.framework (`dc9bf1b` source); loaded its real
PreviewWebView, HTMLTemplate, bundled resources and nonce-only CSP.

- Normal probe: exit 0, **12 assertions passed**.
- Four default-pattern ASTs: expected match counts 3 / 2 / 1 / 2.
- `(a+)+$` against 16,000 `a` characters and `!`: no match, **176,008 steps**, ~9ms.
- Same AST/input with budget 200: **budget status at exactly 200 steps**.
- `a|ab` on `ab`: `[0,2]` (leftmost-longest).
- `😀한` on `x😀한z`: UTF-16 `[1,4]`.
- Two logical lines beginning `ERROR`: one `[0,5]` match per line.
- `import os` across a syntax span: two marks, unchanged text and hljs ancestry.
- Compile budget 2: stopped at exactly 2 steps.
- Nonced inline test of `eval`: rejected by the existing CSP.

Mutation checks on temporary copies, run through the same WebKit runner:

| Mutation | Exit | Actual failure |
|---|---:|---|
| Change `this.used >= this.limit` to `false` | 1 | `precise internal stop: {"status":"complete","matches":[],"steps":176008}` |
| Replace logical-run scan with each node scanned separately | 1 | `cross token DOM mapping`, original code HTML contains no marks |

These checks establish that the assertions distinguish these two broken
mechanisms. They do not establish complete parser/VM correctness, linear all-match
enumeration, complete metering, Settings reuse or production usability.

## Reproduce

From the target worktree, using the existing baseline build from the first review:

```sh
xcrun swiftc -module-cache-path /private/tmp/aynql-review-20260906/ModuleCache.noindex \
  -parse-as-library docs/superpowers/reviews/probes/2026-09-07-metered-nfa/Probe.swift \
  -F /private/tmp/aynql-review-20260906/Build/Products/Debug -framework Shared \
  -Xlinker -rpath -Xlinker /private/tmp/aynql-review-20260906/Build/Products/Debug \
  -o /private/tmp/aynql-metered-probe
/private/tmp/aynql-metered-probe \
  "$PWD/docs/superpowers/reviews/probes/2026-09-07-metered-nfa/probe.js"
```

If that temporary framework has been removed, regenerate with `xcodegen generate`
and build the Tests scheme with `build-for-testing` using the same DerivedData path
first. The command above needs a macOS session where WebKit child processes can
launch; in the review it used sandbox escalation. No app settings were edited.

The runner has a two-second load delay suitable for this local probe, not a robust
future test harness. Production tests must wait for navigation/readiness. The
probe compiler uses manually trusted ASTs, has incomplete grammar/depth handling,
and is not permitted to accept external AST data. The DOM exercise manually maps
two known nodes rather than traversing arbitrary document content.

No production source, dependency or CSP changed. No host build, XCTest suite or
Finder Space test was rerun for this experiment.
