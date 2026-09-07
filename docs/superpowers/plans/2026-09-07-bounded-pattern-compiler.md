# Bounded Pattern Compiler Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this single task inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile restricted user regex into a bounded NFA program without invoking native regex.

**Architecture:** One static JavaScript resource provides a metered parser and Thompson compiler. XCTest loads the actual framework resource into JavaScriptCore and validates accepted languages with a test-only graph interpreter. This task does not connect the resource to HTMLTemplate, renderers, Settings or metadata.

**Tech Stack:** Swift 6 XCTest, JavaScriptCore, static JS; no new dependencies or targets.

**Spec:** [Pattern contract](../reviews/2026-09-07-pattern-execution-and-matching.md).

## Global Constraints

- 256 UTF-16 source units; 16 group nesting levels; explicit repeat maximum 100; 512 emitted states per pattern; 100,000 compile steps per document.
- Budgets are shared between compile calls and cannot be increased through config. Tests may request a smaller budget through the same budget factory.
- Literal Unicode scalars, ASCII shorthand classes, structural groups, alternation, repetition and boundary assertions only. Reject nullable patterns, unsupported syntax and unpaired surrogates.
- Preserve source strings and return per-pattern errors; never fall back to ICU/RegExp.
- Existing CSP, renderer behavior, config and user changes remain unchanged.
- Implement one task at a time. Runtime matching and UI integration require their own later tasks.

## Task 1: Metered parser and NFA compiler

**Files:**
- Create `Shared/Resources/js/bounded-pattern-compiler.js`
- Create `Tests/BoundedPatternCompilerTests.swift`
- Update this plan with actual verification evidence.

**Interfaces:**

```javascript
// Static global BoundedPatternCompiler. No DOM or Swift dependency.
createBudget(limit = 100000) // opaque shared budget, read-only used and limit
compile(source, budget)     // result below; budget optional for a single isolated call
// Success: { status: 'compiled', program: { start, instructions } }
// Failure: { status: 'rejected', reason, offset } (UTF-16 source offset)
// Instructions: char(value,next), class(ranges,next), assert(kind,next),
// split(first,second), match. Ranges are sorted inclusive scalar intervals.
// Assertion kinds: begin, end, word, not-word.
```

- [x] **Step 1: Write behavioral tests before the resource exists.** Load the resource using `Bundle(for: ConfigLoader.self)`. Failure to find it must fail an assertion. Call JS functions with JSValue arguments, never interpolate pattern text into executable source.

```swift
let result = try compile(#"\b(ERROR|FATAL|CRITICAL)\b"#)
XCTAssertEqual(result["status"] as? String, "compiled")
XCTAssertTrue(try accepts(result, "ERROR"))
XCTAssertFalse(try accepts(result, "XERROR"))
```

Include all four defaults; precedence; classes/complements/ranges; quantifier language witnesses; anchors; Unicode; invalid/unsupported/nullable expressions; exact source/depth/repeat/state limits; shared compile budget exhaustion and recovery with a fresh budget; compiled graph edge validity. The test graph interpreter only accepts entire short fixtures and guards its own work, so it is not a production matching engine.

- [x] **Step 2: Regenerate and observe RED.**

```sh
xcodegen generate
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-compiler-20260907 -only-testing:Tests/BoundedPatternCompilerTests
```

Expected: tests fail because the bundled compiler resource does not exist; not a Swift compile or test-runner error.

- [x] **Step 3: Implement the resource.** Parse by precedence (`alternation → concatenation → quantified atom`). Charge budget before token consumption, AST construction, range processing, repeat expansion and state allocation. Reject unsupported escapes, special groups and lazy/possessive modifiers explicitly. Both `(a)` and `(?:a)` are structural groups; empty alternatives parse as nullable and are rejected when the complete expression is nullable. `\b` inside a class is unsupported. Literal `]`, `{`, `}` outside classes require escaping. Reject range endpoints that are shorthand classes.

```javascript
function take(budget) {
  if (budget.used === budget.limit) reject('compile-budget');
  budget.used += 1;
}
// Track nullable at AST construction, not by executing a regex on empty text.
// Compile backwards toward one match state; split represents choices/loops.
// Pre-check each emission against 512; never build an oversized graph then trim.
```

Represent the actual budget with private state, not this illustrative public object. Source length is checked before scanning. Saturated budget failure discards the partial program and preserves the consumed budget. Non-string input returns `invalid-source`.

- [x] **Step 4: Run GREEN and meaningful mutations.** Rerun focused tests. Temporarily bypass compile-budget checking and nullable rejection independently; targeted tests must fail, then restore the source. Check the restored resource before final tests.
- [x] **Step 5: Full existing tests and host build.** Regenerate Xcode project, run Tests scheme and build AllYouNeedQuickLook with the same DerivedData. Report actual counts and warnings. Rendering is not connected in this task, so no new Finder behavior is claimed.
- [x] **Step 6: Review the patch and record results.** Confirm no renderer/config changes and `git diff --check`. Keep existing uncommitted work intact; this session leaves changes reviewable without mixing them into an unrelated commit.

## Evidence

Task 1 complete (2026-09-07), limited to parser/compiler foundation.

- RED: `/private/tmp/aynql-compiler-red.log`, exit 65; 11 setup assertions failed
  because the Shared compiler resource did not exist. XCTest also marked these
  setup-failed cases skipped; this was not a Swift compilation failure.
- GREEN: `/private/tmp/aynql-compiler-green.log`, exit 0; 11 compiler tests passed.
- Budget mutation: `/private/tmp/aynql-compiler-mut-budget.log`, exit 65;
  `testSharedCompileBudgetCannotBeResetOrRaised` failed 3 assertions.
- Nullable mutation: `/private/tmp/aynql-compiler-mut-nullable.log`, exit 65;
  `testMalformedAndNullablePatterns` failed 27 assertions.
- Both mutations restored and byte-compared with the pre-mutation resource.
- Final Tests scheme: `/private/tmp/aynql-compiler-final.log` and
  `/private/tmp/aynql-compiler-final.xcresult`, exit 0; **118 tests, 0 failures**
  (107 baseline plus 11 compiler tests). The compiler tests execute actual JSCore;
  the existing live WebView assertions retain only their existing scope.
- Host app + embedded extension build: `/private/tmp/aynql-compiler-host-build.log`,
  exit 0, ad-hoc signing phase succeeded. Build notes include the existing script
  phase running every time; AppIntents metadata extraction reports no framework
  dependency where applicable. No Swift compiler warning was found in final logs.
- `git diff --check` passed. Production changes are the static compiler resource
  only; no renderer, config, CSP, dependency or target changes. Working-state docs
  were updated, preserving pre-existing uncommitted edits. No commit/push performed.
- New pattern rendering, Settings validation and metadata integration are not
  implemented. No new Finder Space or visual verification was performed.

The next independently testable task is the production metered matcher consuming
this program format. It needs a separate TDD plan before DOM/UI integration. This
plan does not authorize reopening unrelated gutter/language/config decisions.
