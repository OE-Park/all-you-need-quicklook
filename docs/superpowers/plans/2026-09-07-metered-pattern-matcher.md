# Metered Pattern Matcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the bounded compiler's NFA programs against run text under document-wide work budgets, returning UTF-16 match intervals and their resolved emphasis segments, without any native regex.

**Architecture:** One new static JavaScript resource, `Shared/Resources/js/bounded-pattern-matcher.js`, provides a metered single-path Thompson VM (`findMatches`) and a metered interval resolver (`resolveRun`) over the programs emitted by `BoundedPatternCompiler`. XCTest loads both actual bundled resources into JavaScriptCore and asserts language, offset, precedence and budget behavior. This plan connects nothing to HTMLTemplate, the renderers, `PatternHighlighter`, Settings or metadata; those are later tasks.

**Tech Stack:** Swift 6 XCTest, JavaScriptCore, static JS. No new dependencies, targets, CSP sources or config keys.

**Spec:** [Pattern execution and matching contract](../reviews/2026-09-07-pattern-execution-and-matching.md), with [feature design](../specs/2026-09-06-render-time-features-design.md) as background and [the compiler plan](2026-09-07-bounded-pattern-compiler.md) as the producer of the program format consumed here.

## Global Constraints

- Document caps, all fixed in source and unreachable from `config.json`: matching work **2,000,000** metered steps; text inspected **262,144** UTF-16 units; match intervals **2,000**; generated wrappers/segments **4,000**. Per-run cap: a logical run is **16,384** UTF-16 units.
- Budgets are shared across calls through one opaque handle per document. Tests may request smaller limits through the same factory; nothing may raise a cap.
- No native `RegExp`, no `eval`/`new Function`, no WASM, no worker URL, no ICU fallback, no RE2JS dependency, no CSP relaxation.
- Leftmost-longest, non-overlapping matches per program. `^`/`$` address the run boundary. `\d`, `\w`, `\s` and `\b` keep the compiler's ASCII definitions.
- Charge metered work for attempted state transitions, epsilon closure pushes, class range comparisons and match enumeration — including work that is subsequently deduplicated. Check counters before allocation, never after.
- Return UTF-16 offsets that never split a surrogate pair. Matching text is decoded DOM text; malformed input text has defined behavior and is not an error.
- On budget exhaustion return a distinct incomplete result carrying **no** matches for that run: a run commits atomically or not at all. Earlier completed runs are the caller's to keep.
- Use an explicit bounded stack, never recursion proportional to input or program size.
- `reviews/probes/2026-09-07-metered-nfa/` is throwaway research code. Do not copy it into `Shared/`.
- Preserve the per-document nonce, inline bundled scripts, the navigation gate and existing renderer behavior. This plan changes no Swift production source.
- Implement one task at a time; each task ends green with its own commit. Do not push or retarget PR #9 as part of this plan.

---

## Task 1: Metered Thompson matcher

**Files:**
- Create: `Shared/Resources/js/bounded-pattern-matcher.js`
- Create: `Tests/BoundedPatternMatcherTests.swift`
- Modify: `docs/superpowers/plans/2026-09-07-metered-pattern-matcher.md` (Evidence section)

**Interfaces:**

- Consumes: `BoundedPatternCompiler.compile(source, budget)` → `{ status: 'compiled', program: { start, instructions } }`. Instructions are `char(value,next)`, `class(ranges,next)`, `assert(kind,next)`, `split(first,second)`, `match`; `ranges` are sorted inclusive scalar intervals; assertion kinds are `begin`, `end`, `word`, `not-word`.
- Produces:

```javascript
// Static global BoundedPatternMatcher. No DOM, no Swift dependency, no compiler dependency.
createBudget(limits = {})
// limits keys: steps <= 2000000, text <= 262144, intervals <= 2000, segments <= 4000.
// Returns a frozen read-only handle exposing used counters and their limits:
//   steps, stepsLimit, text, textLimit, intervals, intervalsLimit, segments, segmentsLimit
// Throws RangeError for a non-integer, negative or above-maximum limit.

findMatches(program, text, budget)
// { status: 'matched', matches: [{ start, end }] }      complete; may be empty
// { status: 'skipped', reason: 'run-limit' }            this run only; document continues
// { status: 'incomplete', reason }                      run discarded; caller stops matching
//     reason: 'step-budget' | 'interval-limit' | 'text-budget'
// { status: 'rejected', reason }                        caller error, no work charged
//     reason: 'invalid-budget' | 'invalid-text' | 'invalid-program'
```

- [ ] **Step 1: Write the failing tests before the resource exists.**

Create `Tests/BoundedPatternMatcherTests.swift`. Load both actual bundled resources with `Bundle(for: ConfigLoader.self)`; a missing resource must fail an assertion, not silently skip. Never interpolate pattern or input text into evaluated JavaScript source — pass them as `JSValue` arguments.

```swift
import XCTest
import JavaScriptCore
@testable import Shared

final class BoundedPatternMatcherTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        context = try XCTUnwrap(JSContext())
        for name in ["bounded-pattern-compiler", "bounded-pattern-matcher"] {
            let url = try XCTUnwrap(Bundle(for: ConfigLoader.self).url(
                forResource: name, withExtension: "js"
            ), "\(name).js must be bundled in Shared")
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            XCTAssertNil(context.exception)
        }
    }

    private func program(_ pattern: String) throws -> JSValue {
        let result = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternCompiler")?
            .invokeMethod("compile", withArguments: [pattern]))
        XCTAssertEqual(result.forProperty("status")?.toString(), "compiled", pattern)
        return try XCTUnwrap(result.forProperty("program"))
    }

    private func budget(_ limits: [String: Int] = [:]) throws -> JSValue {
        let handle = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternMatcher")?
            .invokeMethod("createBudget", withArguments: [limits]))
        XCTAssertNil(context.exception)
        return handle
    }

    @discardableResult
    private func find(_ pattern: String, _ text: String, _ handle: JSValue? = nil) throws -> JSValue {
        let handle = try handle ?? budget()
        let result = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternMatcher")?
            .invokeMethod("findMatches", withArguments: [try program(pattern), text, handle]))
        XCTAssertNil(context.exception)
        return result
    }

    /// Match intervals as UTF-16 [start, end) pairs.
    private func intervals(_ result: JSValue) throws -> [[Int]] {
        XCTAssertEqual(result.forProperty("status")?.toString(), "matched")
        let matches = try XCTUnwrap(result.forProperty("matches"))
        let count = Int(matches.forProperty("length")?.toInt32() ?? 0)
        return (0..<count).map { index in
            let match = matches.atIndex(index)
            return [Int(match?.forProperty("start")?.toInt32() ?? -1),
                    Int(match?.forProperty("end")?.toInt32() ?? -1)]
        }
    }
}
```

Write these cases in the same file:

```swift
    func testBundledDefaultsMatchLogLineOffsets() throws {
        XCTAssertEqual(try intervals(try find(#"\b(ERROR|FATAL|CRITICAL)\b"#, "2026-01-01 ERROR disk full")),
                       [[11, 16]])
        XCTAssertEqual(try intervals(try find(#"\b(WARN|WARNING)\b"#, "WARNING and WARN")), [[0, 7], [12, 16]])
        XCTAssertEqual(try intervals(try find(#"\b(INFO)\b"#, "INFORMATION")), [])
        XCTAssertEqual(try intervals(try find(#"\b(DEBUG|TRACE)\b"#, "TRACE DEBUG")), [[0, 5], [6, 11]])
    }

    func testLeftmostLongestBeatsFirstAlternative() throws {
        XCTAssertEqual(try intervals(try find("a|ab", "ab")), [[0, 2]])
        XCTAssertEqual(try intervals(try find("ab|a", "ab")), [[0, 2]])
        XCTAssertEqual(try intervals(try find(#"\w+"#, "foo bar")), [[0, 3], [4, 7]])
        XCTAssertEqual(try intervals(try find("a+", "xaaay")), [[1, 4]])
    }

    func testMatchesAreNonOverlappingAndResumeAtTheMatchEnd() throws {
        XCTAssertEqual(try intervals(try find("aa", "aaa")), [[0, 2]])
        XCTAssertEqual(try intervals(try find("aa", "aaaa")), [[0, 2], [2, 4]])
        XCTAssertEqual(try intervals(try find("aba", "ababa")), [[0, 3]])
    }

    func testAnchorsAddressTheRunBoundary() throws {
        XCTAssertEqual(try intervals(try find("^ERROR", "ERROR here")), [[0, 5]])
        XCTAssertEqual(try intervals(try find("^ERROR", " ERROR here")), [])
        XCTAssertEqual(try intervals(try find("done$", "all done")), [[4, 8]])
        XCTAssertEqual(try intervals(try find("done$", "all done now")), [])
        // A literal newline never bridges runs: the caller supplies one run at a time.
        XCTAssertEqual(try intervals(try find("^b", "a\nb")), [])
    }

    func testWordBoundaryUsesTheASCIIDefinition() throws {
        XCTAssertEqual(try intervals(try find(#"\bERROR\b"#, "한ERROR한")), [[1, 6]])
        XCTAssertEqual(try intervals(try find(#"\bERROR\b"#, "xERRORx")), [])
        XCTAssertEqual(try intervals(try find(#"\Bel\B"#, "hello")), [[1, 3]])
    }

    func testOffsetsAreUTF16AndNeverSplitSurrogatePairs() throws {
        XCTAssertEqual(try intervals(try find(#"\w+"#, "a😀bc")), [[0, 1], [3, 5]])
        XCTAssertEqual(try intervals(try find(".", "😀")), [[0, 2]])
        XCTAssertEqual(try intervals(try find("한글", "안녕 한글 hi")), [[3, 5]])
        XCTAssertEqual(try intervals(try find("😀+", "x😀😀x")), [[1, 5]])
    }

    func testMalformedInputTextMatchesByCodeUnitInsteadOfFailing() throws {
        // A lone surrogate is decoded as its own single unit. Defined behavior for
        // malformed *text*; malformed pattern *source* is already rejected at compile.
        let lone = context.evaluateScript("'a' + String.fromCharCode(0xD800) + 'b'")
        let result = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternMatcher")?
            .invokeMethod("findMatches", withArguments: [try program("."), try XCTUnwrap(lone), try budget()]))
        XCTAssertEqual(try intervals(result), [[0, 1], [1, 2], [2, 3]])
        XCTAssertEqual(try intervals(try find(#"\w"#, "a\u{FFFD}b")), [[0, 1], [2, 3]])
    }

    func testStepBudgetExhaustionDiscardsTheWholeRun() throws {
        let handle = try budget(["steps": 5000])
        let text = String(repeating: "a", count: 16_001) + "!"
        let result = try find("(a+)+$", text, handle)
        XCTAssertEqual(result.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(result.forProperty("reason")?.toString(), "step-budget")
        XCTAssertTrue(result.forProperty("matches")?.isUndefined == true)
        XCTAssertEqual(handle.forProperty("steps")?.toInt32(), 5000)
    }

    func testBudgetIsSharedAcrossCallsAndAFreshBudgetRecovers() throws {
        let handle = try budget(["steps": 40])
        _ = try find(#"\w+"#, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", handle)
        let second = try find("a", "a", handle)
        XCTAssertEqual(second.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(second.forProperty("reason")?.toString(), "step-budget")
        XCTAssertEqual(try intervals(try find("a", "a", try budget())), [[0, 1]])
    }

    func testOverlongRunIsSkippedIntactWithoutSpendingTheTextBudget() throws {
        let handle = try budget()
        let result = try find("a", String(repeating: "a", count: 16_385), handle)
        XCTAssertEqual(result.forProperty("status")?.toString(), "skipped")
        XCTAssertEqual(result.forProperty("reason")?.toString(), "run-limit")
        XCTAssertEqual(handle.forProperty("text")?.toInt32(), 0)
        XCTAssertEqual(handle.forProperty("steps")?.toInt32(), 0)
        // A run of exactly the cap is accepted. One match keeps this clear of the interval cap.
        XCTAssertEqual(try intervals(try find("a", String(repeating: " ", count: 16_383) + "a", try budget())),
                       [[16_383, 16_384]])
    }

    func testDocumentTextBudgetStopsAtARunBoundary() throws {
        let handle = try budget(["text": 10])
        XCTAssertEqual(try intervals(try find("a", "aaaaaa", handle)).count, 6)
        let second = try find("a", "aaaaaa", handle)
        XCTAssertEqual(second.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(second.forProperty("reason")?.toString(), "text-budget")
        XCTAssertEqual(handle.forProperty("text")?.toInt32(), 6, "the refused run is not partially scanned")
    }

    func testIntervalLimitDiscardsTheRunItOverflows() throws {
        let handle = try budget(["intervals": 2])
        let result = try find(#"\w+"#, "a b c", handle)
        XCTAssertEqual(result.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(result.forProperty("reason")?.toString(), "interval-limit")
        XCTAssertTrue(result.forProperty("matches")?.isUndefined == true)
        XCTAssertEqual(handle.forProperty("intervals")?.toInt32(), 2)
    }

    func testCallerErrorsAreRejectedWithoutCharging() throws {
        let value = context.evaluateScript("""
        (() => {
          const m = BoundedPatternMatcher, b = m.createBudget();
          const p = BoundedPatternCompiler.compile('a').program;
          let raised = false; try { m.createBudget({ steps: 2000001 }); } catch (e) { raised = true; }
          return { badBudget: m.findMatches(p, 'a', {}).reason,
                   badText: m.findMatches(p, null, b).reason,
                   badProgram: m.findMatches({ start: 0, instructions: [] }, 'a', b).reason,
                   notObject: m.findMatches(null, 'a', b).reason,
                   steps: b.steps, raised };
        })()
        """)
        XCTAssertNil(context.exception)
        XCTAssertEqual(value?.forProperty("badBudget")?.toString(), "invalid-budget")
        XCTAssertEqual(value?.forProperty("badText")?.toString(), "invalid-text")
        XCTAssertEqual(value?.forProperty("badProgram")?.toString(), "invalid-program")
        XCTAssertEqual(value?.forProperty("notObject")?.toString(), "invalid-program")
        XCTAssertEqual(value?.forProperty("steps")?.toInt32(), 0)
        XCTAssertEqual(value?.forProperty("raised")?.toBool(), true)
    }

    func testCountersRiseWithAttemptedWorkIncludingDeduplicatedStates() throws {
        let handle = try budget()
        _ = try find("a", "a", handle)
        let single = Int(handle.forProperty("steps")?.toInt32() ?? 0)
        XCTAssertGreaterThan(single, 0)
        let busy = try budget()
        // Every duplicate alternative is charged when it is attempted, so a run with
        // three redundant branches costs far more than its 200 characters.
        _ = try find("(a|a|a)+b", String(repeating: "a", count: 200), busy)
        let spent = Int(busy.forProperty("steps")?.toInt32() ?? 0)
        XCTAssertGreaterThan(spent, 200 * 3)
        XCTAssertLessThan(spent, 2_000_000)
    }
```

- [ ] **Step 2: Regenerate and observe RED.**

```sh
cd /Users/yohanpark/DevTools/all-you-need-quicklook/.worktrees/feat-render-time-features
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests \
  2>&1 | tee /private/tmp/aynql-matcher-red.log
```

Expected: setup fails on every case because `bounded-pattern-matcher.js` is not bundled. This must be an assertion failure, not a Swift compilation error — fix compilation errors before continuing.

- [ ] **Step 3: Implement the resource.**

Create `Shared/Resources/js/bounded-pattern-matcher.js`. Structure and metering rules:

```javascript
// Shared/Resources/js/bounded-pattern-matcher.js
// Metered Thompson VM over BoundedPatternCompiler programs. No native regex, no DOM.
(function (root) {
    'use strict';
    const MAX_STEPS = 2000000, MAX_TEXT = 262144, MAX_INTERVALS = 2000;
    const MAX_SEGMENTS = 4000, MAX_RUN = 16384;
    const COUNTERS = [['steps', MAX_STEPS], ['text', MAX_TEXT],
                      ['intervals', MAX_INTERVALS], ['segments', MAX_SEGMENTS]];
    const budgets = new WeakMap();
    class Exhausted extends Error {
        constructor(reason) { super(reason); this.reason = reason; }
    }
    // One metering helper for every entry point; Task 2's resolveRun reuses it.
    function stepper(work) {
        return function take() {
            if (work.steps >= work.stepsLimit) throw new Exhausted('step-budget');
            work.steps++;
        };
    }

    function createBudget(limits = {}) {
        const state = {}, view = {};
        for (const [name, max] of COUNTERS) {
            const limit = limits[name] === undefined ? max : limits[name];
            if (!Number.isInteger(limit) || limit < 0 || limit > max) throw new RangeError('match budget');
            state[name] = 0; state[name + 'Limit'] = limit;
            Object.defineProperty(view, name, { get: () => state[name], enumerable: true });
            Object.defineProperty(view, name + 'Limit', { get: () => state[name + 'Limit'], enumerable: true });
        }
        const handle = Object.freeze(view);
        budgets.set(handle, state);
        return handle;
    }

    function findMatches(program, text, budget) {
        const work = budgets.get(budget);
        if (!work) return { status: 'rejected', reason: 'invalid-budget' };
        if (typeof text !== 'string') return { status: 'rejected', reason: 'invalid-text' };
        if (!program || typeof program !== 'object' || !Array.isArray(program.instructions)
            || !Number.isInteger(program.start) || !program.instructions[program.start]) {
            return { status: 'rejected', reason: 'invalid-program' };
        }
        if (text.length > MAX_RUN) return { status: 'skipped', reason: 'run-limit' };
        if (work.text + text.length > work.textLimit) return { status: 'incomplete', reason: 'text-budget' };
        work.text += text.length;                       // charged before any scanning
        // ... VM below ...
    }
    root.BoundedPatternMatcher = Object.freeze({ createBudget, findMatches });
})(globalThis);
```

Inside `findMatches`, implement exactly this VM:

```javascript
        const code = program.instructions;
        const take = stepper(work);                     // one unit of attempted work
        // \w is ASCII-only, so a surrogate code unit is never a word character and
        // charCodeAt needs no pair decoding for \b / \B.
        const isWord = u => u !== undefined && ((u >= 48 && u <= 57) || (u >= 65 && u <= 90)
            || (u >= 97 && u <= 122) || u === 95);
        const wordAt = p => isWord(p >= 0 && p < text.length ? text.charCodeAt(p) : undefined);
        const widthAt = p => text.codePointAt(p) > 0xffff ? 2 : 1;
        function inRanges(ranges, scalar) {
            for (const [lo, hi] of ranges) { take(); if (scalar >= lo && scalar <= hi) return true; }
            return false;
        }
        // Explicit stack; `list` maps pc -> earliest start, so leftmost wins on collision.
        function addThread(list, pc, start, pos) {
            const stack = [[pc, start]];
            while (stack.length) {
                take();                                  // attempted, even if deduplicated below
                const [current, from] = stack.pop();
                const seen = list.get(current);
                if (seen !== undefined && seen <= from) continue;
                list.set(current, from);
                const i = code[current];
                if (i.op === 'split') stack.push([i.first, from], [i.second, from]);
                else if (i.op === 'assert') {
                    const before = wordAt(pos - 1), here = wordAt(pos);
                    const holds = i.kind === 'begin' ? pos === 0
                        : i.kind === 'end' ? pos === text.length
                        : i.kind === 'word' ? before !== here : before === here;
                    if (holds) stack.push([i.next, from]);
                }
            }
        }
        const matches = [];
        function commit(best) {
            if (work.intervals >= work.intervalsLimit) throw new Exhausted('interval-limit');
            work.intervals++;
            matches.push({ start: best.start, end: best.end });
        }
        try {
            let list = new Map(), best = null, pos = 0;
            for (;;) {
                if (best === null) addThread(list, program.start, pos, pos);
                for (const [pc, start] of list) {        // enumerate reached match states
                    take();
                    if (code[pc].op !== 'match') continue;
                    if (best === null || start < best.start
                        || (start === best.start && pos > best.end)) best = { start, end: pos };
                }
                if (best !== null) {                     // a later start can never be leftmost
                    for (const [pc, start] of list) { take(); if (start > best.start) list.delete(pc); }
                }
                if (list.size === 0 || pos === text.length) {
                    if (best !== null) { commit(best); pos = best.end; best = null; list = new Map(); continue; }
                    if (pos === text.length) break;
                    pos += widthAt(pos); list = new Map(); continue;
                }
                const scalar = text.codePointAt(pos), width = scalar > 0xffff ? 2 : 1;
                const next = new Map();
                for (const [pc, start] of list) {
                    take();
                    const i = code[pc];
                    const advances = i.op === 'char' ? scalar === i.value
                        : i.op === 'class' ? inRanges(i.ranges, scalar) : false;
                    if (advances) addThread(next, i.next, start, pos + width);
                }
                list = next; pos += width;
            }
        } catch (e) {
            if (!(e instanceof Exhausted)) throw e;
            return { status: 'incomplete', reason: e.reason };   // run discarded atomically
        }
        return { status: 'matched', matches };
```

Rules the implementation must not break:

- Seed a start thread at every scalar position **while no candidate exists**, so one pass covers all start positions instead of restarting a full scan per position. After a committed match, resume at `best.end`; because the compiler rejects nullable programs, `best.end > best.start`, so the scan always advances.
- Never call `RegExp`, `String.prototype.match`, `normalize`, `eval` or `new Function`. Do not import the compiler; the matcher takes a program object as data.
- Never mutate `program`, `text` or the budget handle. All counters live in the `WeakMap` state.
- Positions are only ever scalar boundaries: advance by `widthAt`, and return `start`/`end` as UTF-16 indices.
- No result object carries partial matches: `incomplete` has no `matches` property.

- [ ] **Step 4: Run the focused tests GREEN.**

```sh
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests \
  2>&1 | tee /private/tmp/aynql-matcher-green.log
```

Expected: all `BoundedPatternMatcherTests` cases pass. Record the count.

- [ ] **Step 5: Run mutations that must fail, then restore.**

Apply each mutation alone, rerun the focused tests, record the failing test names and log path, then restore the file and confirm it is byte-identical to the pre-mutation copy (`cp` it aside first, `diff` after).

1. Delete the `work.steps >= work.stepsLimit` check in `take()` → `testStepBudgetExhaustionDiscardsTheWholeRun` and `testBudgetIsSharedAcrossCallsAndAFreshBudgetRecovers` must fail.
2. Replace the leftmost-longest comparison with `if (best === null) best = { start, end: pos };` → `testLeftmostLongestBeatsFirstAlternative` must fail.
3. Resume scanning at `best.start + 1` instead of `best.end` → `testMatchesAreNonOverlappingAndResumeAtTheMatchEnd` must fail.
4. Return `{ status: 'incomplete', reason: e.reason, matches }` from the catch → `testStepBudgetExhaustionDiscardsTheWholeRun` and `testIntervalLimitDiscardsTheRunItOverflows` must fail.

- [ ] **Step 6: Run the full suite and the host build.**

```sh
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/aynql-matcher 2>&1 | tee /private/tmp/aynql-matcher-final.log
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination 'platform=macOS' \
  build -derivedDataPath /private/tmp/aynql-matcher 2>&1 | tee /private/tmp/aynql-matcher-build.log
```

Expected: the 118 existing tests plus the new matcher cases, 0 failures; host app and embedded extension build with ad-hoc signing. Report actual counts and any Swift warning. No rendering changed, so claim no Finder or visual verification.

- [ ] **Step 7: Record evidence and commit.**

Fill this plan's Evidence section with real log paths, counts, exit codes and the mutation results. Then:

```bash
git add Shared/Resources/js/bounded-pattern-matcher.js Tests/BoundedPatternMatcherTests.swift \
        docs/superpowers/plans/2026-09-07-metered-pattern-matcher.md
git commit -m "feat: add metered Thompson matcher for bounded patterns"
```

Do not push and do not touch PR #9 in this task.

---

## Task 2: Metered interval resolution for a run

**Files:**
- Modify: `Shared/Resources/js/bounded-pattern-matcher.js` (add `resolveRun`, export it)
- Modify: `Tests/BoundedPatternMatcherTests.swift` (add the resolution cases)
- Modify: `docs/superpowers/plans/2026-09-07-metered-pattern-matcher.md` (Evidence section)

**Interfaces:**

- Consumes: Task 1's `createBudget` handle (its `segments`/`segmentsLimit` counters) and arrays of `{ start, end }` intervals as returned by `findMatches`.
- Produces:

```javascript
resolveRun(groups, budget)
// groups: [{ kind: 'level', level: 'error'|'warn'|'info'|'debug', matches: [...] },
//          { kind: 'general', matches: [...] }, ...]
//   Caller order is fixed: the four levels in error, warn, info, debug order,
//   then general patterns in saved order. resolveRun does not re-sort groups.
// { status: 'resolved', segments: [{ start, end, level, general }] }
//   Non-overlapping, ascending, adjacent-identical merged. level is the winning
//   level name or null; general is a boolean. One segment is one future wrapper.
// { status: 'incomplete', reason: 'segment-limit' | 'step-budget' }   run discarded
// { status: 'rejected', reason: 'invalid-budget' | 'invalid-groups' }
```

- [ ] **Step 1: Write the failing tests.**

Add these helpers and cases to the existing `BoundedPatternMatcherTests` class.
XCTestCase classes cannot share private helpers and this repository has no shared
test base class, so extending the class reuses `setUpWithError` and `budget(_:)`
instead of duplicating them:

```swift
    private func resolve(_ groups: [[String: Any]], _ handle: JSValue? = nil) throws -> JSValue {
        let handle = try handle ?? budget()
        let result = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternMatcher")?
            .invokeMethod("resolveRun", withArguments: [groups, handle]))
        XCTAssertNil(context.exception)
        return result
    }

    private func level(_ name: String, _ pairs: [[Int]]) -> [String: Any] {
        ["kind": "level", "level": name, "matches": pairs.map { ["start": $0[0], "end": $0[1]] }]
    }

    private func general(_ pairs: [[Int]]) -> [String: Any] {
        ["kind": "general", "matches": pairs.map { ["start": $0[0], "end": $0[1]] }]
    }

    /// Segments as (start, end, level ?? "-", general) tuples for readable assertions.
    private func segments(_ result: JSValue) throws -> [String] {
        XCTAssertEqual(result.forProperty("status")?.toString(), "resolved")
        let list = try XCTUnwrap(result.forProperty("segments"))
        let count = Int(list.forProperty("length")?.toInt32() ?? 0)
        return (0..<count).map { index in
            let s = list.atIndex(index)
            let name = s?.forProperty("level")?.isNull == true ? "-" : (s?.forProperty("level")?.toString() ?? "?")
            return "\(s?.forProperty("start")?.toInt32() ?? -1)-\(s?.forProperty("end")?.toInt32() ?? -1)"
                + ":\(name):\(s?.forProperty("general")?.toBool() == true ? "g" : "-")"
        }
    }

    func testGeneralPatternsUnionIntoOneStyle() throws {
        XCTAssertEqual(try segments(try resolve([general([[0, 4], [2, 7]]), general([[9, 11]])])),
                       ["0-7:-:g", "9-11:-:g"])
    }

    func testAdjacentIdenticalSegmentsMerge() throws {
        XCTAssertEqual(try segments(try resolve([general([[0, 3], [3, 6]])])), ["0-6:-:g"])
    }

    func testLevelPrecedenceIsErrorWarnInfoDebugPerCoveredInterval() throws {
        XCTAssertEqual(try segments(try resolve([level("error", [[4, 9]]), level("warn", [[0, 6]])])),
                       ["0-4:warn:-", "4-9:error:-"])
        XCTAssertEqual(try segments(try resolve([level("info", [[0, 10]]), level("debug", [[2, 4]])])),
                       ["0-10:info:-"])
    }

    func testGeneralEmphasisAndLevelColorCoexistOnOneSegment() throws {
        XCTAssertEqual(try segments(try resolve([level("error", [[0, 5]]), general([[3, 8]])])),
                       ["0-3:error:-", "3-5:error:g", "5-8:-:g"])
    }

    func testEmptyInputResolvesToNoSegments() throws {
        XCTAssertEqual(try segments(try resolve([])), [])
        XCTAssertEqual(try segments(try resolve([general([]), level("error", [])])), [])
    }

    func testSegmentLimitDiscardsTheRunAtomically() throws {
        let handle = try budget(["segments": 2])
        let result = try resolve([general([[0, 1], [2, 3], [4, 5]])], handle)
        XCTAssertEqual(result.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(result.forProperty("reason")?.toString(), "segment-limit")
        XCTAssertTrue(result.forProperty("segments")?.isUndefined == true)
        XCTAssertEqual(handle.forProperty("segments")?.toInt32(), 2)
    }

    func testResolutionChargesTheSharedStepBudget() throws {
        let handle = try budget(["steps": 4])
        let result = try resolve([general([[0, 1], [2, 3], [4, 5], [6, 7]])], handle)
        XCTAssertEqual(result.forProperty("status")?.toString(), "incomplete")
        XCTAssertEqual(result.forProperty("reason")?.toString(), "step-budget")
        XCTAssertEqual(handle.forProperty("steps")?.toInt32(), 4)
    }

    func testMalformedGroupsAreRejected() throws {
        let value = context.evaluateScript("""
        (() => {
          const m = BoundedPatternMatcher, b = m.createBudget();
          return { notArray: m.resolveRun(null, b).reason,
                   badKind: m.resolveRun([{ kind: 'other', matches: [] }], b).reason,
                   badLevel: m.resolveRun([{ kind: 'level', level: 'nope', matches: [] }], b).reason,
                   badPair: m.resolveRun([{ kind: 'general', matches: [{ start: 3, end: 1 }] }], b).reason,
                   badBudget: m.resolveRun([], {}).reason, steps: b.steps };
        })()
        """)
        XCTAssertNil(context.exception)
        for key in ["notArray", "badKind", "badLevel", "badPair"] {
            XCTAssertEqual(value?.forProperty(key)?.toString(), "invalid-groups", key)
        }
        XCTAssertEqual(value?.forProperty("badBudget")?.toString(), "invalid-budget")
        XCTAssertEqual(value?.forProperty("steps")?.toInt32(), 0)
    }
```

- [ ] **Step 2: Run the focused tests to observe RED.**

```sh
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests \
  2>&1 | tee /private/tmp/aynql-resolve-red.log
```

Expected: only the new resolution cases fail, because `resolveRun` is not a function on `BoundedPatternMatcher`; every Task 1 case still passes.

- [ ] **Step 3: Implement `resolveRun` in the same resource.**

```javascript
    const RANK = { error: 4, warn: 3, info: 2, debug: 1 };

    function resolveRun(groups, budget) {
        const work = budgets.get(budget);
        if (!work) return { status: 'rejected', reason: 'invalid-budget' };
        if (!Array.isArray(groups)) return { status: 'rejected', reason: 'invalid-groups' };
        const events = [];                                // {pos, delta, key}
        for (const group of groups) {
            if (!group || typeof group !== 'object' || !Array.isArray(group.matches)) {
                return { status: 'rejected', reason: 'invalid-groups' };
            }
            const level = group.kind === 'level' ? group.level : null;
            if (group.kind !== 'general' && !(group.kind === 'level' && RANK[level])) {
                return { status: 'rejected', reason: 'invalid-groups' };
            }
            for (const m of group.matches) {
                if (!m || !Number.isInteger(m.start) || !Number.isInteger(m.end) || m.end <= m.start) {
                    return { status: 'rejected', reason: 'invalid-groups' };
                }
                events.push({ pos: m.start, delta: 1, key: level || 'general' },
                            { pos: m.end, delta: -1, key: level || 'general' });
            }
        }
        const take = stepper(work);
        try {
            events.sort((a, b) => { take(); return a.pos - b.pos || a.delta - b.delta; });
            const active = { general: 0, error: 0, warn: 0, info: 0, debug: 0 };
            const segments = [];
            let index = 0, previous = null;
            while (index < events.length) {
                take();
                const pos = events[index].pos;
                if (previous !== null && pos > previous) emit(previous, pos);
                while (index < events.length && events[index].pos === pos) {
                    take(); active[events[index].key] += events[index].delta; index++;
                }
                previous = pos;
            }
            function emit(start, end) {                    // covered slice between two events
                let level = null;
                for (const name of ['error', 'warn', 'info', 'debug']) {
                    take();
                    if (active[name] > 0 && (level === null || RANK[name] > RANK[level])) level = name;
                }
                const general = active.general > 0;
                if (level === null && !general) return;
                const last = segments[segments.length - 1];
                if (last && last.end === start && last.level === level && last.general === general) {
                    last.end = end; return;                // merge, no new wrapper
                }
                if (work.segments >= work.segmentsLimit) throw new Exhausted('segment-limit');
                work.segments++;
                segments.push({ start, end, level, general });
            }
            return { status: 'resolved', segments };
        } catch (e) {
            if (!(e instanceof Exhausted)) throw e;
            return { status: 'incomplete', reason: e.reason };
        }
    }
```

Hoist `emit` above the sweep loop (function declarations hoist, but write it before use for readability), and export it: `Object.freeze({ createBudget, findMatches, resolveRun })`. Validation runs before any metered work, so a rejected call charges nothing.

- [ ] **Step 4: Run the focused tests GREEN.**

```sh
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests \
  2>&1 | tee /private/tmp/aynql-resolve-green.log
```

- [ ] **Step 5: Run mutations that must fail, then restore.**

1. Drop the `RANK[name] > RANK[level]` comparison and take the first active level → `testLevelPrecedenceIsErrorWarnInfoDebugPerCoveredInterval` must fail.
2. Push a segment before the `work.segments >= work.segmentsLimit` check → `testSegmentLimitDiscardsTheRunAtomically` must fail.
3. Skip the adjacent-merge branch → `testAdjacentIdenticalSegmentsMerge` and `testGeneralPatternsUnionIntoOneStyle` must fail.

Restore and `diff` against the saved copy after each.

- [ ] **Step 6: Run the full suite and the host build.**

Same two commands as Task 1 Step 6. Report actual totals and warnings.

- [ ] **Step 7: Record evidence and commit.**

```bash
git add Shared/Resources/js/bounded-pattern-matcher.js Tests/BoundedPatternMatcherTests.swift \
        docs/superpowers/plans/2026-09-07-metered-pattern-matcher.md
git commit -m "feat: resolve bounded pattern matches into non-overlapping segments"
```

---

## Task 3: Update the continuation record

**Files:**
- Modify: `docs/superpowers/HANDOFF.md`
- Modify: `AGENTS.md` (Status section)
- Modify: `docs/superpowers/reviews/2026-09-07-pattern-execution-and-matching.md` (status line only)

- [ ] **Step 1: Rewrite the handoff's implemented-versus-pending table and next task.**

Move "Production matcher" and interval resolution to implemented, with the exact API block above. State plainly what is still absent: logical-line and prose-run extraction, protected-subtree boundaries, DOM offset mapping and node splitting, the skip notice, `PatternHighlighter` wiring, HTMLTemplate loading of the resource, Settings validation through the same parser, and log level counts. The next task becomes the run extraction and DOM mapping pass, which needs its own TDD plan.

- [ ] **Step 2: Update `AGENTS.md` "Current work" to name the matcher commit and its evidence, keeping every other Status paragraph intact.**

- [ ] **Step 3: Update the pattern contract's `Current implementation:` line** to say the parser, compiler, matcher and resolver exist and that renderer/Settings integration remains pending. Change nothing else in that document.

- [ ] **Step 4: Verify the record against the tree, then commit.**

```bash
git diff --check
git status --short
git add docs/superpowers/HANDOFF.md AGENTS.md docs/superpowers/reviews/2026-09-07-pattern-execution-and-matching.md
git commit -m "docs: record the metered matcher checkpoint"
```

No claim of Finder, visual or live `WKWebView` verification belongs in this commit: nothing rendered changed.

---

## Out of scope for this plan

These stay unimplemented and must not be started here:

- DOM traversal, run extraction, excluded subtrees, node splitting and wrapper application, and their 20,000-node discovery budget.
- `PatternHighlighter`, `HTMLTemplate` script loading, the skip notice, gutter, metadata header and themes.
- Settings pattern editor, its JSCore validation host, and log level counts in the header.
- Config schema changes, legacy `.log.syntaxHighlight=true` behavior and the unknown notebook language fallback.

## Evidence

Fill in during execution. Record for each task: command, log path, exit code, test counts, mutation results with the failing test names, and every check that was **not** run.

- Task 1 (Metered Thompson matcher): DONE.
  - RED: `xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests` → log `/private/tmp/aynql-matcher-red.log`, exit non-zero. All 14 new cases failed on `XCTUnwrap` for `bounded-pattern-matcher.js` (resource not yet bundled) — an assertion failure, not a Swift compile error, as required.
  - GREEN: same command → log `/private/tmp/aynql-matcher-green.log`, `** TEST SUCCEEDED **`, `Executed 14 tests, with 0 failures (0 unexpected)`. (First attempt after writing the resource still failed because `xcodegen generate` had been run before the new `.js` file existed; rerunning `xcodegen generate` picked it up.)
  - Mutations (each applied alone to `Shared/Resources/js/bounded-pattern-matcher.js`, copy saved at `/private/tmp/aynql-matcher-mutations/original.js`, `diff` confirmed byte-identical restore after every mutation):
    1. Removed the `work.steps >= work.stepsLimit` guard in `take()` → log `/private/tmp/aynql-matcher-mutation1.log`: `testBudgetIsSharedAcrossCallsAndAFreshBudgetRecovers` and `testStepBudgetExhaustionDiscardsTheWholeRun` failed (6 failures total, expected two plus their assertion-level sub-failures) — matches brief.
    2. Replaced the leftmost-longest comparison with unconditional `if (best === null) best = { start, end: pos };` → log `/private/tmp/aynql-matcher-mutation2.log`: `testLeftmostLongestBeatsFirstAlternative` failed (also `testOffsetsAreUTF16AndNeverSplitSurrogatePairs`, which also depends on longest-match `+` semantics) — required failure present.
    3. Resumed scanning at `best.start + 1` instead of `best.end` → log `/private/tmp/aynql-matcher-mutation3.log`: `testMatchesAreNonOverlappingAndResumeAtTheMatchEnd` failed (also `testLeftmostLongestBeatsFirstAlternative` and `testOffsetsAreUTF16AndNeverSplitSurrogatePairs`, both of which also assert non-overlap via `+`) — required failure present.
    4. Returned `{ status: 'incomplete', reason: e.reason, matches }` from the catch → log `/private/tmp/aynql-matcher-mutation4.log`: exactly `testStepBudgetExhaustionDiscardsTheWholeRun` and `testIntervalLimitDiscardsTheRunItOverflows` failed (2 failures total) — matches brief precisely.
  - Full suite: `xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-matcher` → log `/private/tmp/aynql-matcher-final.log`, `** TEST SUCCEEDED **`, `Executed 132 tests, with 0 failures (0 unexpected)` (118 pre-existing + 14 new `BoundedPatternMatcherTests`).
  - Host build: `xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination 'platform=macOS' build -derivedDataPath /private/tmp/aynql-matcher` → log `/private/tmp/aynql-matcher-build.log`, `** BUILD SUCCEEDED **`, ad-hoc signed app and embedded `QuickLookExtension.appex`; no Swift warnings.
  - Not run / not claimed: no Finder integration check, no visual/WKWebView verification — this task renders nothing and touches no Swift production source.
- Task 2 (Metered interval resolution for a run): DONE.
  - RED: `xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-matcher -only-testing:Tests/BoundedPatternMatcherTests` → log `/private/tmp/aynql-resolve-red.log`, exit non-zero. `Executed 22 tests, with 35 failures`: exactly the 8 new resolution cases failed (several assert per case, hence 35), each on `resolveRun is not a function` / its knock-on `undefined` assertions; all 14 Task 1 cases still passed.
  - GREEN: same command → log `/private/tmp/aynql-resolve-green.log`, `** TEST SUCCEEDED **`, `Executed 22 tests, with 0 failures (0 unexpected)`.
  - Mutations (each applied alone to `Shared/Resources/js/bounded-pattern-matcher.js`, copy saved at `/private/tmp/aynql-matcher-mutations/original-task2.js`, `diff` confirmed byte-identical restore after every mutation):
    1. Replaced `if (active[name] > 0 && (level === null || RANK[name] > RANK[level])) level = name;` with `if (active[name] > 0 && level === null) level = name;` (drop the RANK comparison, take the first active level) → log `/private/tmp/aynql-resolve-mutation1.log`: `Executed 22 tests, with 0 failures` — **did not fail**, contrary to the brief's Step 5.1 expectation. Root cause: `emit`'s scan order `['error','warn','info','debug']` is already sorted by descending `RANK`, so "first active found" and "highest-rank active" always coincide for this fixed array literal; `RANK[name] > RANK[level]` can never evaluate true once `level` is non-null, because every later name in the loop has strictly lower rank than every earlier one. The comparison is provably dead code given the current implementation, so this specific mutation cannot be killed by any test. Reported per the task's discrepancy-reporting instruction rather than silently changing the brief's Step 3 code or a test's expectation.
    2. Moved `segments.push({ start, end, level, general });` to before the `work.segments >= work.segmentsLimit` check-and-increment → log `/private/tmp/aynql-resolve-mutation2.log`: `Executed 22 tests, with 0 failures` — **did not fail**, contrary to the brief's Step 5.2 expectation. Root cause: the whole sweep runs inside the `try` that surrounds `resolveRun`'s body; on `Exhausted`, the `catch` returns `{ status: 'incomplete', reason }` only and never reads the local `segments` array, so a segment pushed just before the throw is discarded along with the rest of the array regardless of push order. The atomicity contract (no `segments` in an incomplete result) already holds structurally, making this ordering mutation unobservable. Reported per the task's discrepancy-reporting instruction.
    3. Removed the adjacent-merge branch (`const last = segments[...]; if (last && ...) { last.end = end; return; }`) → log `/private/tmp/aynql-resolve-mutation3.log`: `Executed 22 tests, with 4 failures`: `testAdjacentIdenticalSegmentsMerge`, `testGeneralPatternsUnionIntoOneStyle`, and `testLevelPrecedenceIsErrorWarnInfoDebugPerCoveredInterval` (twice, both its assertions) failed — matches the brief's required two plus one incidental extra (that test also happens to depend on merging two same-level slices at `4-6`/`6-9` and `0-2`/`2-4`/`4-10`).
  - Full suite: `xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-matcher` → log `/private/tmp/aynql-resolve-final.log`, `** TEST SUCCEEDED **`, `Executed 140 tests, with 0 failures (0 unexpected)` (118 pre-existing + 22 `BoundedPatternMatcherTests`, up from 14). Console noise from an unrelated WKWebView-hosting test (WebContent XPC/sandbox/pasteboard messages) appears in the log but is not a test failure.
  - Host build: `xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination 'platform=macOS' build -derivedDataPath /private/tmp/aynql-matcher` → log `/private/tmp/aynql-resolve-build.log`, `** BUILD SUCCEEDED **`, ad-hoc signed app with embedded `QuickLookExtension.appex`; no Swift compiler warnings (only an unrelated `xcodebuild: WARNING: Using the first of multiple matching destinations` notice and build-setting names that contain the word "warning").
  - Not run / not claimed: no Finder integration check, no visual/WKWebView verification — this task renders nothing and touches no Swift production source.
  - Self-review finding (non-blocking, code-quality only): the `RANK[name] > RANK[level]` comparison in `emit` and the check-then-push ordering around `work.segments` are both currently redundant given the surrounding structure (see mutations 1 and 2 above). Left as specified in the brief's Step 3 code rather than restructured, since the brief instructs transcribing that block verbatim and both are harmless (correct output, no perf concern at this scale) rather than defects.
- Task 3: _pending_
