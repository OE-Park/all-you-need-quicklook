# JSON/YAML preview routing, markdown formatting, syntax highlight coverage

Branch `fix/bug-review-20260912`. Reported: `.json` / `.yaml` added in Settings
never previewed; `.md` rendered in a different format from the rest; request to
confirm per-language syntax highlighting.

## Root causes

1. **`.json` / `.yaml` never reached the extension.** `public.json` and
   `public.yaml` conform to `public.text`, not to `public.plain-text`. The
   extension declared only `public.plain-text`, `com.apple.log`,
   `net.daringfireball.markdown` and `org.jupyter.notebook`, so `quicklookd`
   never considered it for those files and logged nothing. Settings writes
   `config.json`, which controls rendering only, never type registration.
   Measured with `UTType` on macOS 26 (Darwin 25.6.0):

   ```
   json  -> public.json   supertypes: public.content public.data public.item public.text
   yaml  -> public.yaml   supertypes: public.content public.data public.item public.text
   md    -> net.daringfireball.markdown   ... public.plain-text ...
   ```

2. **Settings-added types rendered uncoloured.** The Add button stores a bare
   `FileTypeConfig()`: `syntaxHighlight` false, `syntaxLanguage` nil. Even once
   routed, a `.json` file rendered as plain text.

3. **Markdown had no block spacing.** `HTMLTemplate`'s
   `* { margin: 0; padding: 0 }` strips every block margin and only
   `.markdown-cell` (the notebook path) restored them. Computed style in the
   rendered document, before the fix:

   ```
   #markdown-content h1  margin=0px/0px  padding-left=0px
   #markdown-content p   margin=0px/0px  padding-left=0px
   #markdown-content ul  margin=0px/0px  padding-left=0px
   blockquote / hr       margin=0px/0px  padding-left=0px
   ```

   `MarkdownRenderer` also ignored `fontSize` and `lineHeight`, which
   `PlainTextRenderer` applies.

4. **Fenced code in a nested second box.** `hljs.highlightElement` adds the
   `hljs` class; the theme gives `.hljs` its own background and
   `pre code.hljs` its own `1em` padding, inside a `pre` that already has
   both.

5. **Unsupported fence languages failed silently.** The bundled
   highlight.js v11.12.0 is the `common` build: 36 languages. For anything
   else it only warns and leaves the block bare:

   ```
   [WARN] Could not find the language 'dockerfile', did you forget to load/include a language module?
   [WARN] Falling back to no-highlight mode for this block.
   ```

## Changes

- `project.yml`: added `public.json`, `public.yaml`, `public.toml` to
  `QLSupportedContentTypes`. Deliberately excluded: `public.xml` and CSV-style
  delimited text (left to the system preview) and `.ts`, which resolves to
  `public.mpeg-2-transport-stream`. Source code needs no entry — it reaches
  `public.plain-text` through `public.source-code`.
- `Shared/Config/SyntaxLanguageMap.swift` (new): extension to highlight.js
  language id, restricted to grammars the bundled build registers. `log` and
  `txt` are deliberately absent.
- `ConfigSchema`: `resolved(with:fileExtension:)` infers `syntaxLanguage` from
  the extension and defaults `syntaxHighlight` on only when a grammar was
  found. Explicit values win both ways; log level patterns suppress inference.
- `HTMLTemplate`: block-spacing rules shared by `.markdown` and
  `.markdown-cell`; `pre code.hljs` background and padding neutralised; new
  `--muted` token for blockquote text (the gutter grey fails contrast for body
  text); `[data-unhighlighted-language]` label.
- `MarkdownRenderer` / `NotebookRenderer`: check `hljs.getLanguage` first, fall
  back to `highlightAuto`, and mark the block when the declared language has no
  grammar.
- `MarkdownRenderer`: applies configured `fontSize` and `lineHeight`. Applies
  `fontFamily` only when the `md` file type names one — the global default is
  `SF Mono`, chosen for code, and inheriting it would set all prose monospace.
- `CSSStringEscaper` (new): extracted from `PlainTextRenderer`, now shared.
- Host app: `sample.json` and `sample.yaml` added to the Preview tab.

## Verification run

- `xcodebuild test -scheme Tests -destination "platform=macOS"` — **226 tests,
  0 failures.** Suite was 213 before.
- Live `WKWebView` DOM assertions (`PreviewWebViewLiveTests`, 7 new): markdown
  block margins and list indent are non-zero; fenced code has a transparent
  background and no padding of its own; `dockerfile` falls back to detection
  and carries `data-unhighlighted-language`; `json` uses its own grammar and is
  unmarked; a Settings-added `.json` and an unconfigured `.yaml` produce hljs
  tokens with their own colour; `.log` keeps `.log-error` and never reaches the
  syntax path.
- Mutation checks, both confirmed to fail the new tests when reverted:
  removing the markdown spacing CSS (7 live failures) and removing the
  extension language lookup (14 failures across three suites).
- Visual check in a Chromium-family browser, light and dark: markdown spacing,
  single-box fences, theme switching (`hljs-attr` `#005cc5` light /
  `#79c0ff` dark).
- `xcodebuild -scheme AllYouNeedQuickLook build` — **BUILD SUCCEEDED.**
- Built `.appex` `Info.plist` confirmed to carry the seven content types;
  `sample.json` / `sample.yaml` confirmed present in the app bundle.

## Verification corpus

`scripts/make-preview-corpus.py` generates a 70-file corpus into
`~/Desktop/AYNQL-test` (3.3 MiB). `AGENTS.md` now requires renderer,
template, escaping, `SyntaxLanguageMap` and content-type changes to be
verified against it. It is generated rather than committed so the size cases
stay out of the repository and so each file's reason is recorded in code.

Boundary cases were computed against `boundedPreview`'s own arithmetic and
land where intended:

| File | lines | UTF-16 units | Cut by |
|---|---:|---:|---|
| `json-9999-lines.json` | 9,999 | 243,822 | not cut |
| `json-10000-lines.json` | 10,000 | 243,847 | line budget |
| `json-12000-lines.json` | 12,000 | 294,846 | line budget |
| `json-wide-lines.json` | 9,001 | 673,821 | byte budget |
| `json-one-huge-line.json` | 1 | 300,013 | byte budget |
| `emoji-over-budget.txt` | 1 | 300,001 | byte budget (2 units per emoji) |
| `big.log` | 15,000 | 887,190 | byte budget |
| `deeply-nested.json`, `long.md` | — | — | not cut |

### Corpus render probe (scratch, not committed)

All 70 files were rendered through the matching renderer and the documents
checked for integrity. Result: **every document ended with `</html>`, no file's
content contributed a single `</script>`, and every app-controlled script
carried the document nonce.**

Two false alarms were worth the time, because both would have been reported as
defects on a naive reading:

- Counting `<script` directly is invalid. The bundled highlight.js carries the
  regex literal `/<script(?=\s|>)/` in its XML grammar, so every document has
  exactly one unstamped occurrence regardless of content. Baselines have to be
  taken per renderer.
- An empty string is not a valid notebook, so `NotebookRenderer` takes the
  error path, which emits one script fewer. The three files in `08-malformed/`
  deviate for that reason and that reason only.

The corpus also reproduced the known deferred limitation: an unrecognised
`cell_type` fails the whole notebook rather than the single cell
(`08-malformed/unknown-cell-type.ipynb`).

## Install state for the Finder check

The duplicate rows in System Settings were ghost registrations. Nine distinct
`.app` paths were recorded; seven pointed at `/private/tmp` build directories
that no longer existed, and LaunchServices had kept the records. The
`/Applications` copy was a 2026-09-07 build, from before any of this work.

`scripts/install-to-applications.sh --reset-config` (new) was run:

- unregistered all 18 recorded paths, ghosts included
- built Release and installed it to `/Applications`, replacing the old copy
- `codesign --verify --deep --strict` on the installed bundle: **OK**
- installed appex declares all seven content types, `public.json` /
  `public.yaml` / `public.toml` included
- removed the Debug build product from DerivedData
- deleted the App Group `config.json`, so `load()` falls back to the bundled
  `default-config.json`
- restarted `quicklookd`

Verified independently afterwards: exactly one registration
(`/Applications/AllYouNeedQuickLook.app`), no other `.app` on disk under
DerivedData or `/private/tmp`, no `config.json` in the group container.

The discarded config is backed up in this session's scratchpad. It was the
reproduction state — `json` and `yaml` with `syntaxHighlight: true` and no
`syntaxLanguage`, which is exactly the case the extension lookup now covers.

## Not run — still the owner's to verify

- **Finder Space check for `.json`, `.yaml`, `.toml`.** Registration and
  routing cannot be proven from tests, the host Preview tab or `qlmanage -p`.
  The app must be launched once so LaunchServices registers the new content
  types; stale registrations from earlier build locations may need
  `lsregister -u <path>`.
- Whether the system preview wins for any of the three, the way it already
  does for `.txt`.
- Dark-mode check inside Finder's own preview panel.
