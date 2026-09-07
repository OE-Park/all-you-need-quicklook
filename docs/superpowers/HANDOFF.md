# Render-time features — continuation handoff

Updated: 2026-09-07. This is the current continuation checkpoint, not a claim that
the render-time feature set is complete.

## Start here

1. Confirm worktree, branch, HEAD and dirty files. Read `AGENTS.md` and applicable
   `.github/` instructions from that checkout.
2. Read the [pattern contract](reviews/2026-09-07-pattern-execution-and-matching.md).
3. Read the completed [compiler task and evidence](plans/2026-09-07-bounded-pattern-compiler.md),
   then inspect `Shared/Resources/js/bounded-pattern-compiler.js` and
   `Tests/BoundedPatternCompilerTests.swift`.
4. Consult the [feature design](specs/2026-09-06-render-time-features-design.md) and
   [original review](reviews/2026-09-06-render-time-features-codex-review.md) for
   remaining work. The original review's line numbers/hashes describe its dated
   snapshot; some findings have since been addressed in design only.

Local worktree:
`/Users/yohanpark/DevTools/all-you-need-quicklook/.worktrees/feat-render-time-features`

Remote branch: `OE-Park/all-you-need-quicklook:feat/render-time-features`.
This branch is stacked on `feat/host-app-ui` (`b553d9c`, open PR #8 at handoff).
Its Draft PR targets that branch to avoid duplicating the host UI changes. After
#8 merges, inspect ancestry and the PR diff before retargeting to `main`; do not
blindly rebase or force-push. Check GitHub for current state rather than treating
these recorded branch facts as permanent.

The user requested a checkpoint and handoff, not merging or deleting this worktree.
Preserve it for continuation. Other worktrees and root-checkout edits are separate.

## Implemented versus pending

| Area | Current state |
|---|---|
| Restricted regex parser | Implemented in static JS; literals/scalars, classes, structural groups, alternation, repetition, assertions |
| NFA compiler | Implemented; source/depth/repeat/state/compile-work caps, nullable rejection, opaque shared budget |
| Compiler validation | 11 XCTest cases execute the actual bundled resource in JSCore; short language fixtures use an independent test graph interpreter |
| Production matcher | **Not implemented**. No search/match API exists in the resource |
| DOM traversal/emphasis, runtime budgets | **Not implemented** |
| Settings parser adapter, pattern editor, log metadata counts | **Not implemented** |
| Gutter, metadata header, themes, notebook language fixes | **Not implemented** |
| Current renderer behavior | Unchanged by the compiler work; the new resource is bundled but not loaded by HTMLTemplate |

The read-only compiler budget factory accepts a smaller budget for callers/tests;
the maximum is fixed at 100,000. Share one handle across a document's compile calls.
Do not use the optional per-call fresh budget when processing a document's pattern
list. No config key can raise a cap.

```javascript
const b = BoundedPatternCompiler.createBudget();
const result = BoundedPatternCompiler.compile(source, b);
// {status:'compiled', program:{start,instructions}}
// or {status:'rejected', reason, offset} — UTF-16 source offset
// Opcodes: char(value,next), class(ranges,next), assert(kind,next),
// split(first,second), match.
// Assertions: begin, end, word, not-word.
```

Compiler availability does not close the ReDoS finding for the future rendering
pass. Matching, enumeration, DOM discovery, allocation and wrapper application
must also honor their shared budgets. Existing renderer log matching still uses
its old implementation until a separately tested integration task replaces it.

## Next task

Write a focused TDD implementation plan for the **production metered matcher**
consuming the compiler program above. Implement one plan task at a time.

- Use the accepted restricted grammar and leftmost-longest semantics. No native
  `RegExp`, ICU fallback, RE2JS dependency or CSP relaxation.
- Account for attempted state transitions, epsilon closure, class comparisons,
  scalar decoding and match enumeration. Bound allocations before they occur.
- Reject/skip nullable programs through the compiler; still make runtime progress
  and state deduplication explicit. Never scan by restarting unlimited work at
  each input position or silently resetting the document budget.
- Return UTF-16 intervals without splitting surrogate pairs. Define behavior for
  malformed input text separately from the already-rejected malformed pattern
  source. Test Korean, emoji, anchors, overlaps and end-of-input assertions.
- On budget exhaustion, expose a distinct incomplete result; no partial-run
  emphasis or exact full-file counts. Test shared budgets across calls and fresh
  budgets on later previews.
- Keep renderer/Settings wiring out of the initial matcher task. Later tasks need
  logical-line/prose-run extraction, protected-subtree boundaries, atomic DOM
  mapping, status notices and shared-engine validation/counts.
- `reviews/probes/2026-09-07-metered-nfa/` is **throwaway research code**. It takes
  trusted manual ASTs and lacks the complete contract. Do not move it into Shared.

For the broader feature plan, remaining design findings include gutter typography/
whitespace/padding, saved legacy `.log.syntaxHighlight=true` behavior and unknown
notebook language fallback. Resolve these before implementing their features.
The SVG/math skip contract and cross-node matching are specified but not shipped.

## Verification checkpoint

On macOS 26.6.2 / Xcode 26.6 / arm64, the handoff rerun passed:

- `xcodegen generate`.
- Tests scheme: **118 tests, 0 failures** (107 baseline + 11 compiler cases).
- Host application and embedded extension build, including ad-hoc signing.
- Earlier compiler TDD: missing-resource RED; 11-test GREEN; removal of the budget
  guard failed 3 assertions; removal of nullable rejection failed 27 assertions;
  source restored before final testing. See the compiler plan for the sequence.
- Earlier exploratory WKWebView probe: 12 assertions passed and two deliberately
  broken variants failed. This proves selected mechanisms only, not the production
  matcher or DOM pipeline.

No new Finder Space/visual check was run for this non-rendering compiler task.
Baseline live WKWebView tests cover only their existing assertions. The owner's
older dark-mode manual check is still pending. `.md`, `.ipynb`, `.log` Finder
routing was recorded earlier; `.txt` used the system preview in that environment.

Reproduce on macOS (regenerate the ignored Xcode project):

```sh
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS'
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination 'platform=macOS' build
```

For just the compiler, add `-only-testing:Tests/BoundedPatternCompilerTests` to the
test command. Ubuntu/cloud agents must not attempt Xcode or claim local compilation;
use actual macOS CI results and report pending runtime/Finder checks separately.

Local handoff logs: `/private/tmp/aynql-handoff-tests.log`,
`/private/tmp/aynql-handoff-build.log`. Temporary logs/DerivedData are not portable
or committed; this record and the committed tests/probe instructions preserve the
evidence and reproduction path. AppIntents extraction emits the existing warning
about absent AppIntents.framework; there was no Swift compiler warning in the
recorded compiler final build.

## Guardrails and archives

- Preserve per-document nonce, inline bundled scripts and the navigation gate.
- Only app-controlled scripts get a nonce. Supported markdown/raw notebook HTML
  remains markup under CSP; do not escape that feature away.
- Serialize data for its destination and protect HTML script boundaries. The
  existing ScriptEscaping string helpers are not JSON serializers.
- Generated global AI instructions must be edited at their ai-sync source, not
  patched here. This checkout's project instructions are ordinary tracked files.
- The dated `2026-09-06-...-review-prompt.md` is historical; use this handoff to
  continue, not its pre-implementation assumptions.
- Rejected timeout and unmodified RE2JS approaches are recorded in Obsidian:
  `Knowledge/07_DevArchive/정규식에 timeout을 붙여도 미리보기 처리가 오래 멈춘다.md`.
  The vault was found under its parent repository's `obsidian/` ignore rule, not
  as a separate Git repository on this machine. No force-add or vault init was done.

## Copy/paste continuation prompt

```text
Continue OE-Park/all-you-need-quicklook on branch feat/render-time-features.
On this Mac use .worktrees/feat-render-time-features under the repository.
Confirm worktree, branch, HEAD, dirty files and PR base before making changes.
Read AGENTS.md and docs/superpowers/HANDOFF.md, then its linked pattern contract,
compiler plan and actual compiler/tests. The parser/NFA compiler exists; the
production matcher, DOM pipeline and Settings integration do not.
Next: write a focused TDD plan for the metered matcher, then execute one task at
a time. Do not restart the host UI plan or copy the exploratory probe as production
code. Preserve the nonce/CSP and accepted bounded-regex semantics. On Ubuntu do
not run Xcode; obtain compilation/test evidence from macOS CI. On macOS regenerate
with XcodeGen and run relevant tests plus the host build. Separate unit/JSCore,
live WKWebView, visual and Finder checks. Do not mark unrun checks complete.
```
