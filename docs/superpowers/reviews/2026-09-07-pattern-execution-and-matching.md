# Pattern execution and matching — reconsideration

Date: 2026-09-07
Status: bounded-regex direction accepted by user continuation; engine architecture selected; production implementation pending
Current implementation: restricted parser and NFA compiler only; see the
[compiler plan and validation](../plans/2026-09-07-bounded-pattern-compiler.md).
Runtime matching and renderer/Settings integration remain pending. The experiment
and candidate evaluation below describe the earlier feasibility step.
Scope: findings 1 and 3 of the [local design review](2026-09-06-render-time-features-codex-review.md), plus their necessary DOM, settings, and count dependencies.
Baseline: `feat/render-time-features`, HEAD `dc9bf1bbf59c48fe67ae7a2236ec9df22c29a2fe`, with pre-existing uncommitted documentation changes preserved.

## Recommendation

Use a bounded, non-backtracking regex subset. Match logical text runs, then map
match offsets onto the existing DOM text nodes. Keep the current nonce-only CSP
and static inlined app-controlled scripts. Do not execute user patterns through
JavaScript `RegExp` or ICU, including for metadata counts and Settings validation.

The accepted direction makes this compatibility tradeoff: retain the four bundled log patterns,
but reject unsupported custom expressions explicitly. Preserve their JSON values;
an unsupported pattern is not a config decoding error and must never reset the
remaining settings. A request for unrestricted JS regex would require a different
execution architecture and another review.

The design's existing per-text-node algorithm is not repaired by adding the `m`
flag: `import os` still crosses highlighting spans. A timeout around the existing
native regex call is not an execution limit either.

## Execution contract

### Approaches considered

| Approach | Benefit | Cost / disposition |
|---|---|---|
| Metered non-backtracking subset | Bounded added work under the existing inline-script CSP; bundled log patterns remain expressible | Recommended; advanced custom regex compatibility narrows and engine metering needs proof |
| Full JS regex in an independently terminable execution context | Greater JS syntax compatibility | Alternative if that compatibility is required; worker/process lifecycle, cancellation and CSP need separate validation |
| Literal-only general emphasis | Smallest matching surface | Alternative product simplification; still needs a separate bounded policy for existing log regexes |

Do not assume a blob Worker is available: this document's CSP has no worker-src
or child-src and therefore falls back to its nonce-only script-src. A nonce on
the creator script is not a blob URL permission. The fallback is specified in
[CSP Level 3](https://www.w3.org/TR/CSP/#directive-worker-src); actual QuickLook
worker integration has not been tested here. These alternatives do not authorize
a policy change.

The superficially smaller native-RegExp-plus-timer approach is rejected. Its
reusable rationale is recorded in the Obsidian DevArchive note
`정규식에 timeout을 붙여도 미리보기 처리가 오래 멈춘다.md`.

### Language and engine

- Syntax contract: literal Unicode scalars, escaped metacharacters, `.`, character
  classes/ranges/negation, concatenation, alternation, grouping, `?`, `*`, `+`,
  bounded repetitions, `^`, `$`, `\b`, `\B`, `\d`, `\w`, `\s` and their complements.
- Case-sensitive by default. No inline flags, backreferences, lookaround, recursion,
  conditionals, replacement templates, or capture-group output in the first version.
  Grouping is structural; all emphasis applies to the complete match.
- Compiler grammar details: `(x)` and `(?:x)` are structural groups. Dot excludes
  CR, LF, U+2028 and U+2029. Shorthand classes cannot be range endpoints; `\b` and
  `\B` inside classes are unsupported. Escape literal `]`, `{`, `}` outside
  classes. Unpaired surrogate source units are rejected; error offsets use UTF-16.
- `\d` and `\w` use ASCII definitions; `\b` follows that `\w`. Define `\s` as
  `[\t\n\r\f\v ]`. Literal Korean/emoji remain supported. Do not claim ICU Unicode
  character-class compatibility. Unsupported escapes are errors, not literals.
- Matching policy: leftmost-longest, non-overlapping matches per pattern; union
  matches from separate general-highlight patterns. This is explicitly not full
  JavaScript or ICU matching compatibility (`a|ab` on `ab` selects `ab`).
- Use a Thompson-style NFA or equivalent non-backtracking implementation with
  metering inside parsing, expansion, state transitions, epsilon closure and
  match enumeration. Count attempted work even if a state is subsequently deduplicated.
  Starting over at every input position must not escape the shared work budget.
- Do not build a “safe regex” heuristic that ultimately passes accepted input to
  `RegExp`: even `(a+)+$` is in the regular subset and must be safe because of the
  execution algorithm, not because suspicious spelling was rejected.
- Reject patterns capable of zero-length matches using nullable analysis, including
  assertion-only expressions. A conservative rejection is acceptable and should
  explain why. Never rely on a potentially non-advancing `exec` loop.
- The runtime must remain a statically bundled JS interpreter. No `eval`,
  `new Function`, WASM compilation, worker URL or new CSP source is authorized here.
  A library name alone is not proof that the interpreter meets this contract.

Thompson simulation is O(mn) for expression size m and input size n; fixing the
pattern only makes that linear in n. Both quantities therefore need bounds.
See [Russ Cox's algorithm explanation](https://swtch.com/~rsc/regexp/regexp1.html).
[RE2 syntax](https://github.com/google/re2/wiki/syntax) is a compatibility reference,
not an automatic commitment to every RE2 feature.

### Initial implementation limits

Use these numbers as initial implementation caps, **not measured latency guarantees**.
Implementation must expose counters for deterministic boundary tests. Limits
cannot be raised or disabled by config.json.

| Resource | Proposed cap | On overflow |
|---|---:|---|
| General patterns | 32, plus the four fixed log slots | Disable general emphasis for this load; do not silently select the first 32 |
| Pattern source | 256 UTF-16 code units each | Skip that pattern, retain its saved text |
| Group nesting / expanded states | 16 / 512 per pattern | Reject before unbounded recursion or allocation |
| Explicit repeat bound | 100 | Reject before expansion; expanded-state cap still applies |
| Compile work | 100,000 metered steps per document | Stop compiling remaining patterns and report incomplete processing |
| DOM discovery | 20,000 visited nodes, including elements and excluded nodes encountered | Stop discovery and report incomplete processing |
| A logical run | 16,384 UTF-16 units | Skip the run intact; do not split it into false independent matches |
| Text inspected for matching | 262,144 UTF-16 units per document | Finish only work admitted under this budget; stop at a run boundary |
| Matching work | 2,000,000 metered steps per document | Discard unfinished run results, stop remaining matching |
| Match intervals / generated wrappers | 2,000 / 4,000 per document | Discard unfinished run results, preserve already completed runs |

Check counters before work or allocation. A whole-tree `querySelectorAll`, full
unbounded `textContent` concatenation, oversized regex parse, or unlimited match
array created before checking its length violates the contract. Node text length
must be checked before copying/concatenating it. Use an explicit bounded traversal
stack, not recursion proportional to arbitrary document depth.

These limits bound the added pattern work, not marked, KaTeX, highlight.js, WebKit
layout, arbitrary CSS, or total preview time. Cooperative elapsed-time checks can
stop work earlier, but are supplemental; they do not turn a blocking regex call
into a preemptible operation. Scheduling chunks may improve responsiveness after
profiling, but each chunk must obey the same document-wide counters.

Commit emphasis atomically per logical run: collect, match, resolve overlaps and
check the projected wrapper count before touching its nodes. A limit hit must not
leave half of a cross-node match highlighted. Earlier completed runs may remain.
Render one app-controlled notice, independent of `showMetaHeader`, stating that
some pattern emphasis was skipped. Do not interpolate a pattern as HTML in it.

## Matching contract

### Units

| Content | One matching run | Hard boundaries |
|---|---|---|
| Plain text and logs | One logical line | CRLF as one separator; lone CR or LF |
| Markdown fenced/indented code | One logical line of the rendered code text | Newline, code block |
| Notebook code, stream/plain output, traceback/raw preformatted text | One logical line | Newline, cell/output block |
| Markdown and supported HTML prose | One paragraph, heading, table cell, or contiguous inline-text segment of a list item/block | Structural block boundary, `<br>`, excluded subtree |

Matching uses decoded DOM text, before any pattern wrappers. Inline `span`, `em`,
`strong`, links and inline `code` do not create boundaries. Therefore `import os`
survives hljs token spans and `foo **bar**` can match `foo bar`. A pattern never
crosses a paragraph, table cell, notebook cell or code/log line. Multiline regex
matching is deliberately unsupported in this first version; literal newline
patterns cannot bridge these runs.

Use a single traversal with explicit structural boundaries, not overlapping
selectors for `li`, `p`, `pre` that process descendants twice. Structural boundary
tags include `address`, `article`, `aside`, `blockquote`, `caption`, `dd`, `details`,
`div`, `dl`, `dt`, `fieldset`, `figcaption`, `figure`, `footer`, `form`, `h1`–`h6`,
`header`, `hgroup`, `hr`, `li`, `main`, `nav`, `ol`, `p`, `pre`, `section`, `summary`,
`table`, `tbody`, `td`, `tfoot`, `th`, `thead`, `tr`, `ul`. Treat each `pre` as a
special line source. Other HTML containers retain inline continuity within the
nearest boundary. Raw HTML display overrides do not redefine the contract.

For prose, concatenate DOM text exactly: no Unicode normalization and no invented
spaces between nodes. Source whitespace may differ from visually collapsed HTML
whitespace; arbitrary CSS-generated text is outside matching. If visible-whitespace
normalization is desired later, it needs its own offset mapping and fixtures.

`^` and `$` address run boundaries. Thus `^ERROR` still applies independently to
every log line. Log counts use the same line text and matcher, count lines with at
least one match for each level, and never rerun ICU on file content. A line may
count toward multiple levels. Counts are independent of color precedence. If a
level pattern is rejected or processing is incomplete, do not show an exact full
file total: show that count as unavailable with the skip notice. Header metrics
unrelated to patterns can remain Swift-computed; level totals must be filled from
the shared bounded result after the pass. This revises the earlier claim that
MetaHeader can compute these regex counts independently in Swift.

### DOM mapping and exclusions

1. After parse → math → highlight → gutter, collect each admitted run as text
   plus `(textNode, localStart, localEnd, runStart)` segments. Offsets are UTF-16
   for DOM APIs; scalar-aware matching must map back without splitting surrogate
   pairs. Do not modify source strings or code text to manufacture boundaries.
2. Match once over the run, resolve intervals, then distribute intersections onto
   those original nodes. Split nodes from right to left. Keep existing element
   ancestry and syntax classes; never assign parent `innerHTML` or use a Range
   operation that extracts/reparents arbitrary markup.
3. General patterns have one style: union their covered ranges. For overlapping
   log levels, choose `error > warn > info > debug` per covered interval. A general
   emphasis background and a log color may coexist on one wrapper. Do not nest
   wrappers by executing one destructive pass per pattern.
4. Skip `.gutter`, `.meta-header`, `.katex`, app notices, `script`, `style`,
   `template`, `noscript`, `textarea`, `select`, and nodes within non-HTML namespace
   subtrees (including SVG and MathML). Also skip `hidden` and `aria-hidden="true"`
   subtrees. Encountering an excluded subtree ends a run, so text on either side
   is not falsely concatenated. Do not traverse subdocuments or shadow roots.
5. Snapshot eligible nodes before edits; process each load once. The inserted
   emphasis wrappers are not input to another traversal. Raw HTML remains markup
   under the existing CSP; skipping it for matching is not sanitizing it.

## Integration changes required by the proposal

- `PatternHighlighter` becomes a bounded discovery/matching/application pipeline;
  its emitted string cannot be validated by string assertions alone.
- Both `logLevelPatterns` and `highlightPatterns` use this engine. The four default
  patterns fit the proposed grammar. Existing custom ICU patterns are not silently
  rewritten or dropped from persisted config.
- Settings must use the same static parser/compiler and limits, with JSCore as a
  possible native-host embedding of that same source. `NSRegularExpression` is
  no longer the acceptance authority. Embedding and error presentation require
  implementation validation; no JSCore bridge is implemented by this document.
- Compile per preview once, reuse within that preview. Document budgets cover
  both levels and general patterns, with fixed level order followed by saved
  general-pattern order. One invalid pattern does not abort valid siblings.
- Pattern data still requires a JSON-literal serializer plus HTML script-boundary
  protection. The current string-literal helpers are not substitutes.
- Emphasis on decoded text also corrects the old log path's matching against
  HTML-escaped strings. This is an intentional semantics change: `&` means `&`,
  not the five source characters of `&amp;`.

## Validation required before accepting an implementation

- Engine tests: four defaults; unsupported grammar; `(a+)+$` on long failing input;
  counter exhaustion during compilation, state closure and match enumeration;
  nested repetitions; nullable patterns. Assert work caps, not just wall time.
- Semantic fixtures: `import os` across hljs spans; `foo **bar**`; two `^ERROR`
  lines; CRLF; empty/trailing lines; Korean/emoji; entity-decoded `&`; block and
  excluded-subtree boundaries; deterministic overlap priority.
- Limit fixtures: one overlong text node, deep markup, too many elements, many
  small runs, too many matches and a match spanning thousands of nodes. Assert
  no partial-run wrappers and that following previews get fresh budgets.
- Actual PreviewWebView tests: unchanged CSP, nonce-only scripts, positive expected
  match ranges, source `textContent` preservation, hljs class preservation, SVG/
  MathML/KaTeX subtree preservation, notice shown even with header disabled.
- Metadata tests: counts agree with the same matcher, and incomplete scans never
  publish exact counts. Settings and preview must accept/reject the same fixtures.
- Deliberately restore per-node matching or unmetered matching and confirm the
  relevant tests fail. Retaining one hljs span is not an adequate assertion.
- Measure compile/scan/DOM-apply latency separately on actual supported WKWebView;
  test the resulting feature in Finder Space. No current green baseline test
  substitutes for these future checks.

## Engine decision and evidence boundary

Select a project-owned, single-path metered Thompson NFA for the deliberately
restricted grammar. Keep the parser/compiler and VM separable. Do not adopt
unmodified RE2JS or a multi-engine fork for this feature. This is an architecture
choice, not a claim that a production regex engine has been completed.

RE2JS 2.8.6 source at `b5dafa3a565cb6cd12c6edae75f79373230a734e` was inspected in an
isolated temporary clone. Its `RE2.executeEngine` dispatches through literal and
prefilter searches, OnePass, bit-state matching, DFA and NFA; metering only
`Machine.add` cannot govern that API. Parser limits and DFA memory limits are
not a document-wide operation budget. No public compile/match budget callback was
found in the inspected source. This is not a finding that RE2JS has exponential
backtracking: its bit-state path is distinct from unrestricted native RegExp.
See the pinned [dispatcher](https://github.com/le0pard/re2js/blob/b5dafa3a565cb6cd12c6edae75f79373230a734e/src/RE2.js),
[parser](https://github.com/le0pard/re2js/blob/b5dafa3a565cb6cd12c6edae75f79373230a734e/src/Parser.js)
and [NFA](https://github.com/le0pard/re2js/blob/b5dafa3a565cb6cd12c6edae75f79373230a734e/src/Machine.js).

A throwaway VM/compiler-fragment experiment was run through the current
PreviewWebView and its real nonce-only CSP. Twelve checks passed: four manually
constructed default-pattern ASTs, nested repetition failure, exact budget stop,
leftmost-longest choice, UTF-16 emoji offsets, line anchors, cross-token DOM
mapping, compile stop, and CSP refusal of eval. The 16,001-character failing
`(a+)+$` input consumed 176,008 metered steps and about 9ms in the first run;
a 200-step budget stopped at exactly 200. This is a feasibility observation for
this machine/fixture, not a production latency promise.

The prototype takes manually constructed ASTs. It does not parse user regex,
implement the full grammar, enforce every document cap, or integrate Settings,
metadata counts or general DOM discovery. Its counter definitions are provisional;
production counters must cover parsing, class comparisons, expansion and DOM work.
Do not copy the throwaway probe into Shared as an implementation shortcut.

Reproducible source and runner are in [probes](probes/2026-09-07-metered-nfa/README.md).
The host application's source, dependencies, CSP and configuration were not changed.
No new host build/XCTest suite or Finder Space test was run. The temporary Swift
runner compiled against the existing baseline Shared.framework; the actual new
validation is its WebKit assertions, not a fresh baseline build claim.

This continuation settles the restricted-regex direction and engine architecture.
The implementation must still prove the complete parser/VM and budgets under TDD.
The original gutter, persisted-log auto-highlighting and unknown-language findings
remain open; the whole render-time design is not yet ready for implementation.
