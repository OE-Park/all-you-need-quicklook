// Tests/BoundedPatternCompilerTests.swift
import XCTest
import JavaScriptCore
@testable import Shared

final class BoundedPatternCompilerTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        context = try XCTUnwrap(JSContext())
        let url = try XCTUnwrap(Bundle(for: ConfigLoader.self).url(
            forResource: "bounded-pattern-compiler", withExtension: "js"
        ), "bounded compiler must be bundled in Shared")
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        XCTAssertNil(context.exception)
        // Independent whole-input graph interpreter: explores (pc, scalar position)
        // pairs, not the compiler's recursive construction algorithm.
        context.evaluateScript(#"""
        function accepts(program, text) {
            const chars = Array.from(text), seen = new Set(), todo = [[program.start,0]];
            const word = c => c !== undefined && 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.includes(c);
            let visits = 0;
            while (todo.length) {
                if (++visits > 100000) throw Error('test interpreter budget');
                const [pc,pos] = todo.pop(), key = pc+':'+pos;
                if (seen.has(key)) continue;
                seen.add(key);
                const i = program.instructions[pc];
                if (!i) throw Error('invalid edge');
                if (i.op === 'match') { if (pos === chars.length) return true; }
                else if (i.op === 'split') todo.push([i.first,pos],[i.second,pos]);
                else if (i.op === 'assert') {
                    const boundary = word(chars[pos-1]) !== word(chars[pos]);
                    const yes = i.kind === 'begin' ? pos === 0 : i.kind === 'end' ? pos === chars.length : i.kind === 'word' ? boundary : !boundary;
                    if (yes) todo.push([i.next,pos]);
                } else if (pos < chars.length) {
                    const cp = chars[pos].codePointAt(0);
                    const yes = i.op === 'char' ? cp === i.value : i.ranges.some(([lo,hi]) => lo <= cp && cp <= hi);
                    if (yes) todo.push([i.next,pos+1]);
                }
            }
            return false;
        }
        """#)
        XCTAssertNil(context.exception)
    }

    private func compile(_ pattern: String) throws -> JSValue {
        let result = try XCTUnwrap(context.objectForKeyedSubscript("BoundedPatternCompiler")?
            .invokeMethod("compile", withArguments: [pattern]))
        XCTAssertNil(context.exception)
        return result
    }

    private func language(_ pattern: String, yes: [String], no: [String]) throws {
        let result = try compile(pattern)
        XCTAssertEqual(result.forProperty("status")?.toString(), "compiled", pattern)
        guard result.forProperty("status")?.toString() == "compiled" else { return }
        let program = try XCTUnwrap(result.forProperty("program"))
        for (inputs, expected) in [(yes, true), (no, false)] {
            for input in inputs {
                let actual = context.objectForKeyedSubscript("accepts")?.call(withArguments: [program, input])
                XCTAssertNil(context.exception)
                XCTAssertEqual(actual?.toBool(), expected, "\(pattern) on \(input)")
            }
        }
    }

    private func rejected(_ pattern: String, _ reason: String? = nil) throws {
        let result = try compile(pattern)
        XCTAssertEqual(result.forProperty("status")?.toString(), "rejected", pattern)
        if let reason { XCTAssertEqual(result.forProperty("reason")?.toString(), reason, pattern) }
        XCTAssertTrue(result.forProperty("program")?.isUndefined == true)
    }

    func testBundledDefaultsRetainTheirLanguage() throws {
        try language(#"\b(ERROR|FATAL|CRITICAL)\b"#, yes: ["ERROR", "FATAL", "CRITICAL"], no: ["XERROR", "error", "ERRORS"])
        try language(#"\b(WARN|WARNING)\b"#, yes: ["WARN", "WARNING"], no: ["WARNINGS", "WARNX"])
        try language(#"\b(INFO)\b"#, yes: ["INFO"], no: ["INFORMATION"])
        try language(#"\b(DEBUG|TRACE)\b"#, yes: ["DEBUG", "TRACE"], no: ["TRACES"])
    }

    func testAlternationConcatenationAndGroups() throws {
        try language("ab|cd", yes: ["ab", "cd"], no: ["ad", "abcd"])
        try language("a(?:b|c)d", yes: ["abd", "acd"], no: ["ab", "ad"])
        try language("(a|)b", yes: ["ab", "b"], no: ["a", ""])
    }

    func testQuantifierLanguages() throws {
        try language("ab?c", yes: ["ac", "abc"], no: ["abbc"])
        try language("ab*c", yes: ["ac", "abbbc"], no: ["ab"])
        try language("ab+c", yes: ["abc", "abbbc"], no: ["ac"])
        try language("a{2,4}", yes: ["aa", "aaa", "aaaa"], no: ["a", "aaaaa"])
        try language("a{2,}", yes: ["aa", "aaaaaa"], no: ["a"])
        try language("a{0}b", yes: ["b"], no: ["ab"])
        try language("(a+)+$", yes: ["a", "aaaa"], no: ["aaa!", ""])
    }

    func testClassesAndASCIIShorthands() throws {
        try language(#"[a-c\d]+"#, yes: ["a29c"], no: ["d", "한"])
        try language(#"[^a-c]+"#, yes: ["😀한9"], no: ["abc"])
        try language(#"[\D]+"#, yes: ["a한"], no: ["123"])
        try language(#"\w\W\d\D\s\S"#, yes: ["a!9x z"], no: ["한!9x z"])
        try language(#"[\]\\\-]"#, yes: ["]", "\\", "-"], no: ["a"])
        try language(".", yes: ["😀", "한"], no: ["\n", "\r", "\u{2028}", "\u{2029}"])
    }

    func testUnicodeEscapesAndAssertions() throws {
        try language("^😀한$", yes: ["😀한"], no: ["x😀한", "😀"])
        try language(#"a\Bb"#, yes: ["ab"], no: ["a b"])
        try language(#"\^\$\[\]\{\}\(\)\.\*\+\?\|\\"#, yes: ["^$[]{}().*+?|\\"], no: [""])
        try language(#"a\t\n\r\f\vb"#, yes: ["a\t\n\r\u{c}\u{b}b"], no: ["ab"])
    }

    func testUnsupportedSyntaxNeverFallsBack() throws {
        for p in [#"(a)\1"#, "(?=a)a", "(?<=a)b", "(?i)a", "(?<name>a)", "a+?", "a++", #"\p{L}"#, #"\q"#, #"[\b]"#] {
            try rejected(p, "unsupported")
        }
    }

    func testMalformedAndNullablePatterns() throws {
        for p in ["(", "a)", "[z-a]", "[]", "[a", "a{3,2}", "a{,2}", #"[a-\d]"#, "*a", "a**", "a]", "a{", "a}"] {
            try rejected(p)
        }
        for p in ["", "a*", "a?", "a{0}", "a|", "()", "^$", #"\b"#, "(a?)+"] {
            try rejected(p, "nullable")
        }
    }

    func testSourceDepthAndRepeatBounds() throws {
        try language(String(repeating: "a", count: 256), yes: [String(repeating: "a", count: 256)], no: ["a"])
        try rejected(String(repeating: "a", count: 257), "source-limit")
        try language(String(repeating: "(", count: 16) + "a" + String(repeating: ")", count: 16), yes: ["a"], no: ["b"])
        try rejected(String(repeating: "(", count: 17) + "a" + String(repeating: ")", count: 17), "depth-limit")
        try language("a{100}", yes: [String(repeating: "a", count: 100)], no: ["a"])
        try rejected("a{101}", "repeat-limit")
    }

    func testExpansionIsStoppedBeforeOversizedProgramEscapes() throws {
        let good = try compile("(a{100}){5}a{11}")
        XCTAssertEqual(good.forProperty("status")?.toString(), "compiled")
        XCTAssertEqual(good.forProperty("program")?.forProperty("instructions")?.forProperty("length")?.toInt32(), 512)
        try rejected("(a{100}){5}a{12}", "state-limit")
        try rejected("((a{100}){100}){100}", "state-limit")
    }

    func testSharedCompileBudgetCannotBeResetOrRaised() throws {
        let value = context.evaluateScript("""
        (() => {
          const c=BoundedPatternCompiler, b=c.createBudget(2);
          const first=c.compile('abcdef',b), second=c.compile('a',b);
          let raised=false; try { c.createBudget(100001); } catch(e) { raised=true; }
          return {first:first.reason,second:second.reason,used:b.used,raised,
                  fresh:c.compile('a',c.createBudget()).status};
        })()
        """)
        XCTAssertNil(context.exception)
        XCTAssertEqual(value?.forProperty("first")?.toString(), "compile-budget")
        XCTAssertEqual(value?.forProperty("second")?.toString(), "compile-budget")
        XCTAssertEqual(value?.forProperty("used")?.toInt32(), 2)
        XCTAssertEqual(value?.forProperty("raised")?.toBool(), true)
        XCTAssertEqual(value?.forProperty("fresh")?.toString(), "compiled")
    }

    func testPatternPayloadIsDataAndInvalidUnicodeIsRejected() throws {
        try language("</script><script>", yes: ["</script><script>"], no: ["script"])
        let result = context.evaluateScript("BoundedPatternCompiler.compile(String.fromCharCode(0xD800))")
        XCTAssertEqual(result?.forProperty("reason")?.toString(), "invalid-unicode")
        XCTAssertEqual(context.evaluateScript("BoundedPatternCompiler.compile(null).reason")?.toString(), "invalid-source")
    }
}
