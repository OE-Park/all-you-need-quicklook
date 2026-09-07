# External review prompt — render-time preview features

> Historical design-review prompt (2026-09-06). The restricted compiler has since
> been implemented. For current continuation instructions and resolved/open
> findings, start at [HANDOFF.md](../HANDOFF.md). Do not treat the original
> pre-implementation assumptions below as today's repository state.

Paste the block below into GitHub Copilot or Codex. It is written to be used
verbatim; the only thing that changes between tools is the entry note at the top.

**Entry note for GitHub Copilot (cloud agent):**
> Repository `OE-Park/all-you-need-quicklook`, branch `feat/render-time-features`.
> You run on Ubuntu and cannot run Xcode, `xcodebuild`, or QuickLook. Read the
> source and reason about it; do not attempt to build.

**Entry note for Codex (local, macOS):**
> Working directory is `.worktrees/feat-render-time-features` under the repository.
> Confirm branch `feat/render-time-features`, HEAD, dirty files and this worktree's
> `AGENTS.md` before reviewing. You can run
> `xcodegen generate` and `xcodebuild ... -scheme Tests`. Building is optional —
> existing tests do not validate this design, which is not yet implemented.
> Do not report a current passing result unless you actually ran the tests.

---

## The prompt

You are reviewing a **design document for work not yet written**, plus the
existing code it builds on. The goal is to find defects in the design before
anyone implements it.

**Read:**

- `docs/superpowers/specs/2026-09-06-render-time-features-design.md` — the design
- `Shared/Renderers/` — `PlainTextRenderer`, `MarkdownRenderer`, `NotebookRenderer`,
  `HTMLTemplate`, `ScriptEscaping`
- `Shared/Models/ConfigSchema.swift`, `Shared/Models/NotebookSchema.swift`
- `Shared/Config/ConfigLoader.swift`
- `Shared/WebView/PreviewWebView.swift`
- `Shared/Resources/default-config.json`
- `.github/copilot-instructions.md` — the two "learned the hard way" items are load-bearing

### Context you need

This is a macOS QuickLook preview extension. Previews are HTML rendered in a
`WKWebView` loaded via `loadHTMLString`, under a CSP whose `script-src` names a
per-load nonce and nothing else. Bundled JavaScript (marked, highlight.js, KaTeX)
is inlined into the document because the opaque origin makes `<script src>`
impossible. Configuration lives in a shared App Group container as `config.json`
and is read by both the host app and the extension.

**How this project has actually failed, twice:** code that built cleanly, passed
every unit test, and passed every code review turned out to be completely dead at
runtime — a CSP that had never once been applied, and a `marked` option removed
three major versions earlier that was silently ignored. Neither produced an error
message. Both were found only by running the real app. Weight your attention
accordingly: **the interesting defects here are the ones that fail silently.**

### What to look for

Report on these, in this order of value:

1. **Are the three defects the design claims to repair actually real?** The design
   asserts that `NotebookRenderer` still passes `marked` a removed `highlight`
   option, that notebook code cells carry no language class while `NotebookSchema`
   discards the metadata that would supply it, and that
   `default-config.json`'s `"log": { "syntaxHighlight": true }` is unreachable.
   Verify each against the source. A design built on a false premise is worse than
   no design.

2. **The JS pass order.** The design fixes an order (parse → KaTeX → highlight →
   gutter → pattern emphasis) and claims deviation fails silently. Is the stated
   order sufficient, and is the pattern pass's skip list complete? Consider every
   kind of markup that exists in the document by the time it runs.

3. **Regexes crossing the Swift → JavaScript boundary.** User-supplied patterns
   from `config.json` are compiled and executed in the preview. Consider both what
   a pattern could do to the document and what it could do to the process.

4. **Config compatibility.** The design requires that a `config.json` written
   before this change still decodes, because `ConfigLoader.load()` silently
   substitutes the bundled default on any decode error. Is `decodeIfPresent` on
   `GlobalConfig` sufficient to guarantee that? Consider every type in the decode
   path, and consider the reverse direction as well.

5. **The gutter's alignment assumptions.** The design argues line numbers stay
   aligned because both columns inherit the same font and line height and `pre`
   never wraps. Test that argument against each place a gutter would appear.

6. **Behavior changes the design does not name.** Removing
   `PlainTextRenderer.applyLogPatterns` moves pattern matching from
   `NSRegularExpression` to JavaScript `RegExp`. What else changes as a
   consequence of the described edits that the document does not mention?

7. **Input cases the design does not cover.** Think about what real files look
   like, not what test fixtures look like.

8. **Test adequacy.** For each test the design lists, could it actually fail? A
   test that passes against both the correct and the broken implementation is
   worse than no test, because it buys false confidence.

9. **Internal contradictions** between sections of the design, or between the
   design and the code it describes.

### Do not relitigate these

The owner has decided them. Findings that reopen them will be discarded.

- Scope is the four content types already declared (`.md`, `.ipynb`, `.log`,
  `.txt`). No new UTTypes, no `.py`/`.swift`/`.rs` support.
- The metadata header is computed from file content only. The `Renderer`
  protocol does not gain a file URL.
- Pattern emphasis uses one style for all patterns. No per-pattern colors, no
  user-defined log levels; `logLevelPatterns` keeps its four fixed levels.
- Line numbers appear in the plain-text body *and* in markdown and notebook code
  blocks.
- CSS counters were considered and rejected for line numbers, because
  highlight.js emits spans that cross newlines. If you think that reasoning is
  factually wrong, say so — but do not propose counters without addressing it.

### Also out of scope

Style, naming, formatting, comment density, general Swift or JavaScript best
practices, and refactoring unrelated to this design.

### How to report

For each finding:

- **Severity** — Critical (data loss, security, or the feature is dead on
  arrival) / High (wrong behavior for realistic input) / Medium (works, but the
  design will cause avoidable rework)
- **Where** — `file:line`, or the design section
- **The defect** — one sentence
- **The failure** — concrete inputs or state, and the resulting wrong behavior.
  **If you cannot state how it fails, do not report it.** Say "I could not
  determine" rather than filling the gap with a plausible-sounding concern.

Rank findings most severe first. If you find nothing at a severity, say so
explicitly rather than promoting something lesser to fill the slot.

Finish with one paragraph: is this design ready to implement as written, ready
with the listed changes, or does something in it need to be reconsidered?
