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

## PR integration (2026-09-07)

PRs #5, #8 and #9 were squash merged; combined main is `99c1850`.
The subsequent dark-mode check exposed a blank sandboxed host Preview despite
passing XCTest/Finder checks. Host network-client entitlement repair and the
current light/dark verification are recorded in the
[validation report](../validation/2026-09-07-dark-mode.md). Use that report for
the host verification status; the older dark-mode pending note is superseded.

The owner requested conflict resolution and squash merge of PRs #5, #8 and #9.
The integration workspace is `.worktrees/pr-merge`; existing feature worktrees
and root uncommitted changes are preserved. Check GitHub for the current merge
state and use a fresh main checkout for continuation after the PRs land.

The host integration includes main's image timeout/resource policy and escaping
regressions, explicit nonce plumbing, notebook code-fence highlighting, unknown
text-language fallback, and one-shot navigation admission. Its 130 tests and
host build passed; Finder Space verified md/ipynb/log using the current build's
extension path. The 41 compiler/matcher tests are additional and do not connect
the pattern engine to rendering. Final combined validation: 171 tests passed (130 host integration + 11 compiler
+ 30 matcher/resolver), including existing live WKWebView assertions; host and
embedded extension build passed. No renderer, host UI or extension source differs
from the Finder-verified host integration. No additional Finder check was run
for these unloaded JS resources. `git diff --check` passed.

## Implemented versus pending

| Area | Current state |
|---|---|
| Restricted regex parser | Implemented in static JS; literals/scalars, classes, structural groups, alternation, repetition, assertions |
| NFA compiler | Implemented; source/depth/repeat/state/compile-work caps, nullable rejection, opaque shared budget |
| Metered Thompson matcher (`findMatches`) | Implemented; leftmost-longest, non-overlapping, UTF-16-safe offsets, shared step/text/interval budget |
| Run interval resolver (`resolveRun`) | Implemented; non-overlapping ascending segments, error>warn>info>debug precedence, adjacent-identical merge, shared segment/step budget |
| Compiler + matcher validation | 41 cases execute the bundled resources in JSCore (11 compiler and 30 matcher/resolver tests); see the current integration checkpoint for the full-suite count; short language fixtures use an independent test graph interpreter |
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
//  {status:'rejected', reason:'invalid-budget'|'invalid-text'|'invalid-program'|'internal-error'}
BoundedPatternMatcher.resolveRun(groups, budget)
//  groups: [{kind:'level', level:'error'|'warn'|'info'|'debug', matches:[...]}, {kind:'general', matches:[...]}]
//  {status:'resolved', segments:[{start,end,level,general}]}   non-overlapping, ascending, adjacent-identical merged
//  {status:'incomplete', reason:'segment-limit'|'step-budget'} | {status:'rejected', reason:'invalid-budget'|'invalid-groups'|'internal-error'}
```

Matching is leftmost-longest and non-overlapping, `^`/`$` address the run
boundary, and offsets are UTF-16 and never split a surrogate pair.

Matcher and resolver availability do not close the ReDoS finding for the future
rendering pass. DOM discovery, allocation and wrapper application must still
honor their own shared budgets. Existing renderer log matching still uses its
old implementation until a separately tested integration task replaces it.

## Measured budget behaviors the integration plan must settle

Three behaviors of the shipped matcher/resolver were measured by the final
whole-branch review and are not yet decided policy. The binding contract's
table rows are annotated with a short marker pointing here; this is the
detail. Settle all three before or during the run-extraction-and-DOM-mapping
plan, because the first one may change `findMatches`'s signature.

- **Text budget is charged per pattern-scan, not per run.** `findMatches`
  charges `text.length` on every call, and the caller must call it once per
  (run, pattern) — once per level pattern and once per general pattern over
  the same run text. Effective document coverage is therefore
  `262,144 / patternCount`, not 262,144 characters of document text as the
  contract's table row reads. Measured: five patterns run over one
  1,000-character run charge `text = 5000` on the shared budget. Driving the
  four bundled default log patterns over ordinary log lines covers
  **65,478 characters** of actual log text before the budget stops; with the
  design's full complement of 32 general patterns plus the 4 fixed level
  patterns (36 scans per run), it falls to roughly 7.3 KB. Resolving this may
  mean changing `findMatches` to take all of a run's programs in one call and
  charge `text` once — a signature change, not a cap change.
- **The 2,000 match-interval cap is per document, not per run.** A single
  crafted run — `"ERROR "` repeated 2,730 times — exhausts the interval
  budget by itself, discarding that run's matches and stopping all further
  matching in the document. A legitimate log file with 3,000+ ERROR lines
  hits the same wall with no adversarial input at all.
- **Worst-case matching is O(n²·m), not the O(mn) the contract cites.**
  Thread-seeding stops once a candidate match exists, and the scan resumes at
  the match end only after potentially running to end-of-run first, so a
  user-authored pattern of the shape `a[a]*b|a` over 16,384 `a` characters
  consumes the *entire* 2,000,000-step document budget on that one run. It
  stays fully metered the whole time — degraded emphasis for that run, never
  a hang — and the four bundled default patterns remain linear at roughly 12
  steps per character. Exhausting the full step budget on that adversarial
  input took about 37 ms in Node.

These were run by the reviewer in Node as read-only probes against the
checked-in resource, not as checked-in XCTest cases. The differential fuzz
run in the same review (14,702 pattern/text pairs over literals, classes,
negated classes, `.`, alternation, grouping and quantifiers, plus 8,924 pairs
adding `^`, `$`, `\b`, `\B`, all diffed against a reference leftmost-longest
matcher, 0 mismatches) is likewise not a checked-in test — record that
distinction if a future task cites it as coverage.

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
- Remaining minor findings: duplicated surrogate-width logic and the dead
  `RANK[name] > RANK[level]` comparison after pre-sorting. Revisit or explicitly
  defer them in the integration plan. `4b29114` already fixed the null-budget
  RangeError, inherited level names, negative starts, counter coverage and
  engine-defect reporting; do not triage them as outstanding.
- `internal-error` means an engine defect; counters already charged remain
  charged and partial results are discarded. It is distinct from caller errors.
- `reviews/probes/2026-09-07-metered-nfa/` remains **throwaway research code**;
  do not move it into `Shared/`.

For the broader feature plan, remaining design findings include gutter
typography/whitespace/padding, saved legacy `.log.syntaxHighlight=true`
behavior and the unknown notebook language fallback. Resolve these before
implementing their features. The SVG/math skip contract and cross-node
matching are specified but not shipped.

## Historical verification checkpoint (before 4b29114)

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
