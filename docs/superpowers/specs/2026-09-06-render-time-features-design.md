# Render-time preview features — design

**Date:** 2026-09-06
**Status:** approved, awaiting implementation plan
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
Finder would require declaring each concrete UTType in `QLSupportedContentTypes`
(parent-UTI matching is not supported), and each declaration competes with the
system's own text preview. That is a separate decision with its own risks, and
it is deliberately not taken here.

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
   removed that option in v5 and the bundled build is v15, so the call is
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

Five new units under `Shared/Renderers/`. All are pure functions over strings,
so the existing string-level test style reaches them.

| Unit | Responsibility | Depends on |
|---|---|---|
| `MetaHeader` | Compute per-type metrics, emit the `<header>` | nothing but content and config |
| `LineNumbers` | Gutter markup (Swift) and the code-block gutter pass (JS) | nothing |
| `PatternHighlighter` | Emit the JS text-node pass for `logLevelPatterns` and `highlightPatterns` | `ScriptEscaping` |
| `SyntaxLanguage` | Decide the language for a block | `NotebookSchema` |
| `ThemeCatalog` | List bundled themes, return the selected light/dark CSS pair | resources |

**Boundary rule:** a renderer composes these and does not reach inside them.
Each takes strings and returns strings.

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
highlightPatterns: [String] = []          // regexes, one emphasis style
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
`resolved.logLevelPatterns` is present, emit line count plus per-level counts;
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

## Pattern emphasis: text nodes only

The current `applyLogPatterns` runs in Swift on plain text and is safe only
because it runs on the path where no highlighting happens. Applying a regex to
already-highlighted HTML would match inside tag attributes and corrupt the
markup. Coexisting with highlighting makes the text-node restriction mandatory.

- Walk with `TreeWalker(NodeFilter.SHOW_TEXT)`, skipping any node with an
  ancestor matching `.gutter`, `.meta-header`, `script`, or `style`.
- Replace a matched text node with a fragment. Never assign `innerHTML` on a
  parent — that is what would destroy the highlighting.
- Patterns reach JS as a JSON literal through `ScriptEscaping`, never by string
  concatenation.
- Each pattern is compiled in its own `try`/`catch`. One malformed regex in
  `config.json` must not stop the others.
- The regex dialect changes from ICU (`NSRegularExpression`) to JavaScript
  `RegExp`. The four default log patterns are valid in both. Documented for
  users who wrote their own.

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

Patterns are validated on entry with `NSRegularExpression` and an invalid one is
rejected with an inline message rather than saved. This is a convenience, not the
safety mechanism: ICU accepts expressions JavaScript rejects, and `config.json`
can be edited outside the app, so the per-pattern `try`/`catch` in the JS pass
remains the actual guarantee.

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
- One invalid regex does not prevent the remaining patterns from applying
- Each fix is reverted to confirm a test goes red

A green suite is not evidence that a preview renders. This project has twice had
confident, well-reviewed work turn out to be dead on arrival, both times caught
only by running the real thing. Finder plus spacebar remains the final check;
`qlmanage -p` does not substitute for it.

## Error handling

| Condition | Behavior |
|---|---|
| Unknown theme name | Fall back to the default |
| Invalid regex in config | Skip that pattern, apply the rest |
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
