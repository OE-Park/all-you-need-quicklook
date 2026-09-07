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
| Metered Thompson matcher (`findMatches`) | Implemented; leftmost-longest, non-overlapping, UTF-16-safe offsets, shared step/text/interval budget |
| Run interval resolver (`resolveRun`) | Implemented; non-overlapping ascending segments, error>warn>info>debug precedence, adjacent-identical merge, shared segment/step budget |
| Compiler + matcher validation | 143 XCTest cases in the Tests scheme execute the actual bundled resources in JSCore (118 baseline includes 11 compiler cases; 25 in `BoundedPatternMatcherTests`); short language fixtures use an independent test graph interpreter |
| Logical-line/prose-run extraction, protected-subtree boundaries, DOM offset mapping, node splitting, the 20,000-node DOM discovery budget | **Not implemented** |
| Wrapper application, the skip notice, `PatternHighlighter` | **Not implemented** |
| HTMLTemplate loading of either JS resource | **Not implemented**; neither resource is loaded by any renderer yet |
| Settings pattern validation through the same parser, log level counts in the metadata header | **Not implemented** |
| Gutter, metadata header, themes, unknown notebook language fallback | **Not implemented** |
| Current renderer behavior | Unchanged; the compiler and matcher resources are bundled but not loaded, and existing renderer log matching still uses its old implementation |

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

The matcher/resolver share one opaque budget handle across a whole document's
`findMatches` and `resolveRun` calls; nothing in `config.json` can raise a cap.

```javascript
BoundedPatternMatcher.createBudget(limits)   // steps<=2000000, text<=262144, intervals<=2000, segments<=4000
BoundedPatternMatcher.findMatches(program, text, budget)
//  {status:'matched', matches:[{start,end}]} | {status:'skipped', reason:'run-limit'}
//  {status:'incomplete', reason:'step-budget'|'interval-limit'|'text-budget'}   no matches
//  {status:'rejected', reason:'invalid-budget'|'invalid-text'|'invalid-program'}
BoundedPatternMatcher.resolveRun(groups, budget)
//  groups: [{kind:'level', level:'error'|'warn'|'info'|'debug', matches:[...]}, {kind:'general', matches:[...]}]
//  {status:'resolved', segments:[{start,end,level,general}]}   non-overlapping, ascending, adjacent-identical merged
//  {status:'incomplete', reason:'segment-limit'|'step-budget'} | {status:'rejected', reason:'invalid-budget'|'invalid-groups'}
```

Matching is leftmost-longest and non-overlapping, `^`/`$` address the run
boundary, and offsets are UTF-16 and never split a surrogate pair.

Matcher and resolver availability do not close the ReDoS finding for the future
rendering pass. DOM discovery, allocation and wrapper application must still
honor their own shared budgets. Existing renderer log matching still uses its
old implementation until a separately tested integration task replaces it.

## Next task

Write a focused TDD implementation plan for the **run extraction and DOM
mapping pass**, then execute it one task at a time. Do not begin
implementation before that plan exists.

- Walk the live DOM to find logical-line and prose text runs, respecting
  protected-subtree boundaries (code fences, math, SVG, and whatever else the
  design specifies as excluded). Define and test an explicit DOM discovery
  budget — the design's figure is 20,000 nodes — fixed in source and
  unreachable from `config.json`.
- Map `BoundedPatternMatcher.findMatches`/`resolveRun` UTF-16 offsets back onto
  DOM text node ranges, including node splitting at match boundaries. Never
  split a surrogate pair, and never let a match cross a boundary it wasn't run
  against.
- Apply the resulting wrapper elements without touching markup outside the
  matched offsets, and add the skip notice for runs/documents that come back
  `incomplete` or `skipped`.
- Wire `PatternHighlighter` to call the matcher/resolver with one budget handle
  per document, and load `bounded-pattern-compiler.js` and
  `bounded-pattern-matcher.js` from `HTMLTemplate` — neither resource is loaded
  by any renderer today.
- Keep Settings pattern validation, log level counts in the metadata header,
  gutter, themes and the unknown notebook language fallback out of this task;
  they remain later work per the design.
- Before planning, triage the deferred minor findings from the two matcher task
  reviews (full detail in `plans/2026-09-07-metered-pattern-matcher.md`
  Evidence section): `createBudget(null)` throws `TypeError` rather than the
  documented `RangeError`; the surrogate-width rule is written twice
  (`widthAt` and an inline ternary); program validation only checks
  `instructions[start]`, so an out-of-range program edge throws a raw
  `TypeError` instead of a rejection; the `RANK[name] > RANK[level]`
  comparison in `emit` is dead code given the pre-sorted scan order;
  `RANK[level]` truthiness would accept an inherited `Object.prototype`
  property name; no test covers a negative `start` offset or reads
  `segments`/`segmentsLimit` directly. Fix or explicitly re-defer each one in
  the new plan.
- `reviews/probes/2026-09-07-metered-nfa/` remains **throwaway research code**;
  do not move it into `Shared/`.

For the broader feature plan, remaining design findings include gutter
typography/whitespace/padding, saved legacy `.log.syntaxHighlight=true`
behavior and the unknown notebook language fallback. Resolve these before
implementing their features. The SVG/math skip contract and cross-node
matching are specified but not shipped.

## Verification checkpoint

On macOS 26.6.2 / Xcode 26.6 / arm64, at HEAD `f88828c`:

- `xcodegen generate`.
- Tests scheme: **143 tests, 0 failures** (118 baseline + 25
  `BoundedPatternMatcherTests`), `** TEST SUCCEEDED **`.
- Host application and embedded extension build `** BUILD SUCCEEDED **`,
  ad-hoc signed (framework, then appex with entitlements, then app). The only
  build warning is the pre-existing `appintentsmetadataprocessor` "No
  AppIntents.framework dependency found" notice; no Swift compiler warning.

History, oldest first, each item labeled with the task it belongs to:

- **Compiler task** (`bounded-pattern-compiler.js`, the checkpoint before the
  matcher existed): missing-resource RED; 11-test GREEN reaching 118 total
  (107 baseline + 11 compiler); removing the budget guard failed 3 assertions;
  removing nullable rejection failed 27 assertions; source restored before
  final testing. See the compiler plan for the full sequence.
- **Matcher Task 1** (metered Thompson matcher, `findMatches`): RED before the
  resource existed — all 14 new cases failed on `XCTUnwrap` for the missing
  `bounded-pattern-matcher.js` (an assertion failure, not a compile error),
  log `/private/tmp/aynql-matcher-red.log`. GREEN: 14 tests, 0 failures, log
  `/private/tmp/aynql-matcher-green.log`. Four mutations, each applied alone
  to the resource and reverted afterward: removing the step-budget guard in
  `take()` failed the two predicted budget tests (6 failures counting
  sub-assertions); breaking the leftmost-longest comparison failed
  `testLeftmostLongestBeatsFirstAlternative` (plus
  `testOffsetsAreUTF16AndNeverSplitSurrogatePairs`, which also depends on
  longest-match semantics); resuming at `best.start + 1` instead of
  `best.end` failed `testMatchesAreNonOverlappingAndResumeAtTheMatchEnd`
  (plus the same two overlap-dependent tests); returning matches from the
  exhaustion catch failed exactly the two predicted tests (2 failures). Full
  suite after this task: 132 tests, 0 failures (118 + 14). Host build
  succeeded.
- **Matcher Task 2** (run interval resolution, `resolveRun`): RED — 22 tests,
  35 failures: the 8 new resolution cases failed on `resolveRun is not a
  function` and its knock-on assertions; all 14 Task 1 cases still passed.
  GREEN: 22 tests, 0 failures. Three mutations: removing the adjacent-merge
  branch failed 4 tests (`testAdjacentIdenticalSegmentsMerge`,
  `testGeneralPatternsUnionIntoOneStyle`, and
  `testLevelPrecedenceIsErrorWarnInfoDebugPerCoveredInterval` twice) —
  matches the brief's prediction. The other two predicted mutations proved
  **unkillable** by the existing tests; recorded honestly as evidence about
  what the tests can and cannot catch, not as a defect that was fixed:
  dropping the `RANK[name] > RANK[level]` comparison in favor of "first
  active level found" produced 0 failures, because `emit`'s scan order
  (`error`, `warn`, `info`, `debug`) is already sorted by descending rank, so
  "first found" and "highest rank" always coincide for that fixed array —
  the comparison is dead code given the current iteration order. Moving
  `segments.push` to before the segment-limit check-and-increment also
  produced 0 failures, because the whole sweep runs inside the `try` around
  `resolveRun`'s body, and on `Exhausted` the `catch` returns only
  `{status, reason}` without ever reading the local `segments` array, so a
  segment pushed just before the throw is discarded along with the rest
  regardless of push order — the ordering is unobservable. Full suite after
  this task: 140 tests, 0 failures (118 + 22). Host build succeeded.
- **Fix round 1** (post-review: meter `resolveRun`'s validation loop before
  event allocation): moved `take()` creation ahead of the validation loop and
  charged one step per group/match examined before that item's own
  malformed-input check, so an already-exhausted budget now returns
  `incomplete` before a malformed-input report. Added
  `testExhaustedBudgetSkipsValidationOnWellFormedGroups`,
  `testStepBudgetIsSharedAcrossFindMatchesAndResolveRun`,
  `testBudgetExhaustedByFindMatchesStopsResolveRunToo`, and amended
  `testMalformedGroupsAreRejected` to assert the exact charge per malformed
  shape. This brings `BoundedPatternMatcherTests` to 25 and the full suite to
  the **143** reported above.
- **Earlier exploratory WKWebView probe** (pre-compiler-task research): 12
  assertions passed and two deliberately broken variants failed. This proves
  selected mechanisms only, not the production matcher or DOM pipeline.

No Finder Space, visual, or live `WKWebView` check was run for any of this
work — nothing rendered changed across the parser, compiler, matcher, or
resolver commits. Baseline live WKWebView tests cover only their existing
assertions. The owner's older dark-mode manual check is still pending. `.md`,
`.ipynb`, `.log` Finder routing was recorded earlier; `.txt` used the system
preview in that environment.

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
`/private/tmp/aynql-handoff-build.log`; matcher-task logs
`/private/tmp/aynql-matcher-*.log` and `/private/tmp/aynql-resolve-*.log`.
Temporary logs/DerivedData are not portable or committed; this record and the
committed tests/probe instructions preserve the evidence and reproduction path.
AppIntents extraction emits the existing warning about absent
AppIntents.framework; there was no Swift compiler warning in any of the
recorded final builds.

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
compiler plan, matcher plan and the actual compiler/matcher/tests. The parser,
NFA compiler, metered matcher and run resolver exist; the DOM extraction/mapping
pass, PatternHighlighter wiring, HTMLTemplate resource loading and Settings
integration do not.
Next: write a focused TDD plan for the run extraction and DOM mapping pass, then
execute one task at a time. Triage the deferred findings listed in HANDOFF's Next
task section first. Do not restart the host UI plan or copy the exploratory probe
as production code. Preserve the nonce/CSP and accepted bounded-regex semantics.
On Ubuntu do not run Xcode; obtain compilation/test evidence from macOS CI. On
macOS regenerate with XcodeGen and run relevant tests plus the host build.
Separate unit/JSCore, live WKWebView, visual and Finder checks. Do not mark
unrun checks complete.
```
