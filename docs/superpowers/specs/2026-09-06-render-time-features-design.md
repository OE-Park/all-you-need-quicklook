# Render-time preview features — design

**Date:** 2026-09-06
**Status:** under revision after design review; not implementation-ready
**Pattern revision (2026-09-07):** the bounded-regex direction is accepted and
uses a project-owned metered NFA. The [pattern contract](../reviews/2026-09-07-pattern-execution-and-matching.md)
is authoritative for grammar, budgets, matching units and failure behavior.
Its prototype proves selected mechanisms, not production implementation. Other
review findings remain open.
The parser/NFA compiler foundation is now implemented and verified under the
[compiler plan](../plans/2026-09-07-bounded-pattern-compiler.md); matching, DOM and
Settings integration remain pending. This does not close the other review findings.
**Depends on:** `feat/host-app-ui` (PR #8) — the nonce, `ScriptEscaping`, and the
inlined library template all come from there.

## Goal

Add the preview features that can be decided entirely at render time: a metadata
header, line numbers that survive syntax highlighting, a selectable highlight
theme, and pattern-based emphasis. Along the way, repair three highlighting
defects that already ship.

Nothing here needs the preview to be interactive. That constraint is not a
simplification — Apple provides no API to add chrome, buttons, or a search field
to a Quick Look preview, and whether click and key events reach a third-party
extension's view is undocumented. Everything in this document is settled before
the document is handed to the panel.

## Scope

**In:** the four content types the extension already declares — `.md`, `.ipynb`,
`.log`, `.txt`.

**Out:** new content types. Highlighting `.py`, `.swift`, `.rs` and friends in
Finder is outside this design. In the recorded `.log` check, declaring the
`public.plain-text` ancestor did not select this extension; declaring `com.apple.log`
did. Any new declaration needs a routing check against the system preview. That
is a separate decision with its own risks, and it is deliberately not taken here.

**Out:** per-pattern colors and user-defined log levels. `logLevelPatterns` keeps
its four fixed levels. The new pattern feature applies one emphasis style to a
list of expressions.

## Current state

Some of this already exists, partly.

| | Today |
|---|---|
| Line numbers | `PlainTextRenderer` only, and **only when highlighting is off** — the two paths are mutually exclusive |
| Log level colors | Four fixed levels, same exclusivity |
| Metadata header | Does not exist |
| Highlighting | highlight.js v11.12.0, common build, 36 languages, bundled and inlined |

### Three defects this design repairs

1. **`NotebookRenderer` still calls `marked.setOptions({highlight: …})`.** marked
   removed that option in v8 and the bundled build is v15, so the call is
   silently ignored and code fences inside notebook markdown cells are not
   highlighted. This is the same defect already fixed in `MarkdownRenderer`; it
   has a second habitat.

2. **Notebook code cells carry no language class.** `hljs.highlightElement` is
   called on a bare `<code>`, so it guesses per cell with `highlightAuto`, and
   short cells guess wrong. The answer is in the notebook's
   `metadata.language_info.name`, but `NotebookSchema` discards metadata
   entirely — `init(from:)` never decodes it and `encode(to:)` writes an empty
   dictionary.

3. **`default-config.json` sets `"log": { "syntaxHighlight": true }`, which is
   dead.** `renderWithSyntaxHighlight` also requires `syntaxLanguage`, which is
   absent, so the highlighted path is never entered — and that is the only
   reason log level colors currently work. The config states something the code
   does not do.

## Constraint: the config file must keep decoding

`ConfigLoader.load()` catches every decode error and silently returns the
bundled default. Adding a non-optional field to `GlobalConfig` would therefore
make every existing `config.json` fail to decode and **reset the user's settings
without a word**. This is the same shape as the Reset-to-Default defect already
found in this project.

Every new field is decoded with `decodeIfPresent` through a hand-written
`init(from:)`. A config written before this change must decode successfully and
keep its values. This is a hard requirement with a regression test, not a
nice-to-have.

`version` stays at `1`. The design is constrained to need no migration.

## Architecture

Five composition units under `Shared/Renderers/`, with a separate static bounded
pattern engine resource. String tests cover composition only; the pattern compiler,
VM and DOM mapping need the behavioral checks in the pattern contract.

| Unit | Responsibility | Depends on |
|---|---|---|
| `MetaHeader` | Compute per-type metrics, emit the `<header>` | nothing but content and config |
| `LineNumbers` | Gutter markup (Swift) and the code-block gutter pass (JS) | nothing |
| `PatternHighlighter` | Compose the bounded logical-run matcher and text-node application pass | `ScriptEscaping`, shared metered engine |
| `SyntaxLanguage` | Decide the language for a block | `NotebookSchema` |
| `ThemeCatalog` | List bundled themes, return the selected light/dark CSS pair | resources |

**Boundary rule:** a renderer composes these and does not reach inside them.
Composition emits strings; the runtime matcher additionally owns bounded state
and returns match intervals, count completeness and skip reasons.

Modified: `ConfigSchema`, `NotebookSchema`, `HTMLTemplate`, the three renderers,
`SettingsView`, `default-config.json`.

**Removed:** `PlainTextRenderer.applyLogPatterns` and its per-line `<span>`
generation. Those two are the only reason the highlighted and non-highlighted
paths differ; with both gone the branch collapses to one path.

## Config schema

`GlobalConfig` gains three fields:

```swift
syntaxTheme: String         = "github"   // global only
showMetaHeader: Bool        = true
highlightPatterns: [String] = []          // bounded regex subset, one emphasis style
```

`FileTypeConfig` gains `showMetaHeader: Bool?` and `highlightPatterns: [String]?`.
The theme is a property of the document, not of a file type, so it is not
overridable per type.

`ResolvedFileTypeConfig` gains the resolved forms of all three.

`logLevelPatterns` is untouched. It stays `.log`-specific. `highlightPatterns` is
a separate axis that applies to every type. Both are executed by the same JS pass
(below), which is what lets them coexist with highlighting.

## Assembly

All three renderers take the same shape:

```
resolved = config.resolvedConfig(for: ext)
header   = MetaHeader.html(...)          // only when resolved.showMetaHeader
body     = <renderer-specific>
passes   = LineNumbers.script + PatternHighlighter.script
HTMLTemplate.wrap(header + body + passes, theme: resolved.syntaxTheme, nonce:)
```

### JS pass order is part of the correctness

Departing from this order fails silently.

1. `marked.parse` / notebook markdown cells → DOM
2. KaTeX
3. `hljs.highlightElement`
4. Line-number gutter injection — must be after 3
5. Pattern emphasis — after 3, because 3 overwrites `<code>`; and it must skip
   the gutter's digits injected by 4

The header is the first element of the body in every renderer, above the content
and outside any scrolling code block. It must survive the Column View sidebar,
which is far narrower than the preview panel, so it wraps rather than truncating
and carries no fixed widths.

### Per renderer

**`PlainTextRenderer`** — one path now.

Header items are chosen by config shape, not by hardcoding an extension: when
`resolved.logLevelPatterns` is present, emit line count plus per-level count slots
filled by the bounded JS matcher (unavailable when incomplete);
otherwise line, word and character counts.

Highlighting: when `syntaxHighlight` is set, use `syntaxLanguage` if given and
`highlightAuto` otherwise. That fallback is new — today a missing language means
nothing happens at all.

Because that fallback would newly colorize `.log` files with a guessed language
and fight the level colors, `default-config.json` changes `"log"` to
`"syntaxHighlight": false`. This makes the config state what the code already
does; it does not change rendering.

**`MarkdownRenderer`** — header carries the first ATX `#` title (escaped), word
count, and reading time. A document with no `#` heading omits the title item
rather than substituting a filename; the panel already shows the filename.
Reading time is `max(1, round(words / 200))` minutes, so a short document reads
as "1 min" rather than "0 min". The body is unchanged; the two new
passes are appended.

**`NotebookRenderer`** — header carries the language or kernel, code and markdown
cell counts, and how many cells have been executed. `setOptions({highlight:…})`
is replaced with a `hljs.highlightElement` post-pass, matching `MarkdownRenderer`.
Code cells get `class="language-<lang>"`.

`NotebookSchema` gains decoding for `metadata.language_info.name` and
`metadata.kernelspec`. Since `encode(to:)` currently writes an empty metadata
dictionary, whatever is decoded is written back so round-trip tests keep passing.

## Line numbers: a gutter column

```html
<div class="code-block">
  <span class="gutter" aria-hidden="true">1
2
3</span>
  <pre><code class="language-x">…</code></pre>
</div>
```

CSS counters were considered and rejected. A counter needs one element per line,
and highlight.js emits `<span>`s that cross newlines — a block comment or a
multi-line string produces one span covering several lines — so highlighted
markup cannot be split per line without corrupting it.

The gutter avoids the problem by never being inside `<code>`. It is a sibling.
Highlighting rewrites `<code>` and cannot touch it.

- Layout: `grid-template-columns: max-content 1fr`.
- Alignment holds because both columns inherit the same `font` and `line-height`,
  and `pre` keeps `overflow-x: auto`, so lines never wrap.
- `user-select: none` and `aria-hidden` so copying the code does not pick up the
  numbers.
- For markdown fences and notebook cells, a JS pass counts newlines in each
  `pre code`'s `textContent` and builds the same markup. It runs after
  highlighting and only prepends a sibling.

## Pattern emphasis: bounded logical runs

Use the [2026-09-07 pattern contract](../reviews/2026-09-07-pattern-execution-and-matching.md).
User patterns are compiled by one bounded parser and run through one metered NFA;
never pass them to native JavaScript RegExp or NSRegularExpression. This includes
Settings validation and metadata level counts. Existing custom pattern strings
remain stored when unsupported; skipping them must not trigger a config reset.

Code/log/preformatted output is matched one logical line at a time. Prose uses
structural paragraph/heading/table-cell/inline-run boundaries. Concatenate eligible
DOM text across inline formatting and hljs spans, match the logical run, and map
UTF-16 intervals back onto the original text nodes. Preserve element ancestry and
source text. Do not match each text node independently or regex generated HTML.

The contract fixes grammar, leftmost-longest semantics, Unicode handling, overlap
priority, all compile/scan/DOM limits, atomic per-run application and skip notices.
Skip math, non-HTML namespaces, gutters, metadata and other protected subtrees;
they form boundaries, not gaps to concatenate across. Partial scans must not
publish exact full-file log counts. All app-controlled scripts retain the same
fresh document nonce and JSON data retains script-boundary protection.

## Themes

`ThemeCatalog` bundles six highlight.js themes as resources and inlines only the
selected light/dark pair at render time. The rendered document therefore does not
grow — only the app bundle does, by roughly 12 KB, against the ~470 KB of
libraries already inlined into every preview.

The six, chosen to cover the common preferences without becoming a catalog to
maintain: `github` (default, the current hardcoded pair), `atom-one`, `nord`,
`monokai`, `solarized`, `stackoverflow`. A theme that ships light and dark
variants is paired; a single-mode theme is used for both. An unrecognized name
falls back to `github`.

## Settings

`SettingsView` gains a theme picker, a metadata-header toggle, and an editor for
the pattern list.

Patterns are validated by the same bounded parser/compiler used in previews.
Use the same static JS source in a native JSCore validation adapter; no separate
ICU acceptance rule. Unsupported grammar or exceeded limits produce an inline
reason and are not accepted as new edits. Previously saved unsupported patterns
remain visible and preserved until the user edits or removes them. Runtime checks
remain mandatory for externally edited config and apply to log patterns too.

## Testing

String level, matching the existing style:

- `MetaHeader` items for each type
- `LineNumbers` gutter for an N-line input
- `ThemeCatalog` returns the right pair, and falls back for an unknown name
- `SyntaxLanguage` resolution order
- **A `config.json` containing none of the new keys decodes successfully and
  keeps its existing values** — the regression test for the silent-reset trap
- `PatternHighlighter` emits escaped JSON, not concatenated strings

Live `WKWebView`, the class of test that caught the CSP hole:

- Gutter line count equals source line count
- After the pattern pass, `<code>` still contains `hljs-` classes — the evidence
  that emphasis did not destroy highlighting
- One invalid/unsupported pattern does not prevent valid siblings from applying
- Exact cross-node match ranges, work-counter exhaustion, atomic per-run skipping,
  namespace preservation and count completeness, as specified in the pattern contract
- Each fix is reverted to confirm a test goes red

A green suite is not evidence that a preview renders. This project has twice had
confident, well-reviewed work turn out to be dead on arrival, both times caught
only by running the real thing. Finder plus spacebar remains the final check;
`qlmanage -p` does not substitute for it.

## Error handling

| Condition | Behavior |
|---|---|
| Unknown theme name | Fall back to the default |
| Invalid or unsupported regex in config | Preserve saved text, skip that pattern, show a reason; continue valid siblings |
| Pattern processing budget exhausted | Stop unfinished work without partial-run markup; show skip notice and no exact incomplete totals |
| Notebook without `language_info` | `highlightAuto` |
| `showMetaHeader` false | Emit no header element at all |
| Config missing new keys | Decode successfully with defaults |

## Deferred

- New content types and their UTType declarations
- Per-pattern colors and user-defined log levels
- Data-based previews (`QLPreviewProvider` / `QLPreviewReply`). Attachments with
  `cid:` references would replace the ~470 KB of inlined libraries, but the
  system would render the HTML, which removes the `WKWebView` and with it the
  CSP injection, the nonce, and the navigation delegate. Not a trade to make
  casually.
- Spotlight's `queryString` for highlighting a searched term. It arrives only
  through `preparePreviewOfSearchableItem`, which requires CoreSpotlight
  indexing and does not fire for a file opened from Finder.
