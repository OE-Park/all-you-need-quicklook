// Tests/BoundedPatternMatcherTests.swift
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
}
