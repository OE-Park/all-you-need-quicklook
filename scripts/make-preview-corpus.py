#!/usr/bin/env python3
"""Generate the preview verification corpus.

The corpus is what the Finder Space check is run against. It is generated
rather than committed because the size-limit cases are large and because a
generator states *why* each file exists, which a directory of samples cannot.

Usage:
    python3 scripts/make-preview-corpus.py [destination]

Default destination is ~/Desktop/AYNQL-test. The destination is wiped and
rebuilt, so do not keep anything else there.
"""

import base64
import json
import os
import shutil
import struct
import sys
import zlib
from pathlib import Path

DEST = Path(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/AYNQL-test").expanduser()

# The bounds PlainTextRenderer.boundedPreview enforces.
MAX_UTF16_UNITS = 262_144
MAX_LINES = 10_000


def write(relative, content, encoding="utf-8", newline="\n"):
    path = DEST / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        with open(path, "w", encoding=encoding, newline=newline) as handle:
            handle.write(content)
    return path


# --------------------------------------------------------------------------
# 01 - the reported bug: types that never reached the extension
# --------------------------------------------------------------------------

write("01-newly-routed/basic.json", json.dumps({
    "name": "all-you-need-quicklook",
    "version": "1.0.0",
    "enabled": True,
    "disabled": False,
    "nothing": None,
    "retries": 3,
    "timeout": 1.5,
    "negative": -42,
    "exponent": 6.02e23,
    "tags": ["quicklook", "preview", "macos"],
    "server": {"host": "localhost", "port": 8080,
               "tls": {"enabled": False, "cert": "/etc/ssl/cert.pem"}},
    "empty_object": {},
    "empty_array": [],
    "deep": {"a": {"b": {"c": {"d": {"e": "bottom"}}}}},
}, indent=2) + "\n")

write("01-newly-routed/basic.yaml", """\
# Every YAML token kind the grammar colours
name: all-you-need-quicklook
version: 1.0.0
enabled: true
disabled: false
nothing: ~
also_nothing: null
retries: 3
timeout: 1.5
exponent: 6.02e23
quoted: "double"
single: 'single'

tags:
  - quicklook
  - preview
  - macos

server:
  host: localhost
  port: 8080
  tls:
    enabled: false
    cert: /etc/ssl/cert.pem

defaults: &defaults
  adapter: postgres
  encoding: utf8

development:
  <<: *defaults
  database: aynql_dev

folded: >
  A folded block scalar joins
  these lines with spaces.

literal: |
  A literal block scalar
    keeps this indentation
  exactly as written.

inline_map: {a: 1, b: 2}
inline_seq: [1, 2, 3]
date: 2026-09-21
""")

# .yml must behave identically to .yaml -- both resolve to public.yaml.
write("01-newly-routed/basic.yml", (DEST / "01-newly-routed/basic.yaml").read_text())

write("01-newly-routed/multi-document.yaml", """\
# Three documents in one file
---
kind: Service
metadata:
  name: frontend
---
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 3
---
kind: ConfigMap
data:
  LOG_LEVEL: debug
""")

write("01-newly-routed/basic.toml", """\
# highlight.js has no TOML grammar. `toml` is its own alias for `ini`,
# so this renders with the INI grammar -- headers and keys coloured,
# TOML-only syntax (arrays of tables, dotted keys) not specially handled.
title = "All You Need QuickLook"
enabled = true
retries = 3
timeout = 1.5
tags = ["quicklook", "preview"]

[server]
host = "localhost"
port = 8080

[server.tls]
enabled = false
cert = "/etc/ssl/cert.pem"

[[plugins]]
name = "marked"
version = "15.0.12"

[[plugins]]
name = "highlight.js"
version = "11.12.0"

[literal]
windows_path = 'C:\\Users\\name'
multiline = \"\"\"
spanning
lines
\"\"\"
""")

write("01-newly-routed/gitconfig-style.cfg", """\
# .cfg also resolves to public.toml on macOS
[core]
editor = vim
autocrlf = false

[remote "origin"]
url = https://example.invalid/repo.git
fetch = +refs/heads/*:refs/remotes/origin/*

[alias]
lg = log --oneline --graph --decorate
""")

write("01-newly-routed/minified.json",
      json.dumps({"compact": True, "values": list(range(60)),
                  "nested": {"a": [1, 2, {"b": "c"}]}}, separators=(",", ":")) + "\n")

write("01-newly-routed/single-scalar.json", "42\n")
write("01-newly-routed/empty-object.json", "{}\n")
write("01-newly-routed/empty-file.json", "")


# --------------------------------------------------------------------------
# 02 - markdown formatting
# --------------------------------------------------------------------------

write("02-markdown/format-check.md", r"""# Heading 1 — block spacing

This paragraph must sit clear of the heading above it. Before the fix every
block computed `margin: 0` and everything ran together. Inline `code` should
be a grey chip, not bare text.

## Heading 2 — lists

- first item
- second item
  - nested item, indented past the parent bullet
  - another nested item
    - third level
- third item

1. first
2. second
   1. nested ordered
3. third

- [x] routing fixed
- [ ] Finder check still to run

### Heading 3 — quotes and rules

> A blockquote. Check the text is legible in **both** light and dark mode —
> it used to use the line-number grey, which fails contrast for body text.
>
> Second paragraph inside the quote.
>
> > Nested quote.

---

Text after a horizontal rule.

## Fences the bundle HAS — coloured, no label

```json
{"name": "demo", "count": 3, "ok": true, "nothing": null}
```

```yaml
name: demo
list:
  - one
flag: true
```

```swift
struct Preview: View {
    let title: String
    var body: some View { Text(title).font(.headline) }
}
```

```python
def fib(n: int) -> int:
    return n if n <= 1 else fib(n - 1) + fib(n - 2)
```

```bash
xcodebuild test -scheme Tests -destination "platform=macOS"
```

```sql
SELECT name, count(*) FROM users WHERE active = true GROUP BY name;
```

```diff
- let old = true
+ let new = false
```

```xml
<config><server host="localhost" port="8080"/></config>
```

```css
.preview { background: var(--bg); color: var(--text); }
```

## Fences the bundle does NOT have — label expected

Each must show a small grey `no highlighter for "…"` label, with best-effort
colour from auto-detection underneath.

```dockerfile
FROM alpine:3.19
RUN apk add --no-cache curl
CMD ["/bin/sh"]
```

```terraform
resource "aws_s3_bucket" "example" {
  bucket = "my-bucket"
}
```

```scala
case class Point(x: Int, y: Int)
```

```haskell
main :: IO ()
main = putStrLn "hello"
```

## Fence with no language — plain, no label

```
just some text
  with indentation preserved
```

## Table

| Feature | Status | Note |
|---------|--------|------|
| Markdown | Supported | this file |
| JSON | Supported | newly routed |
| YAML | Supported | newly routed |
| XML | System preview | deliberately not claimed |

## Math

Inline: $E = mc^2$ and $\alpha + \beta = \gamma$

Block:

$$\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}$$

Note the renderer escapes `$` for the JavaScript template literal it passes
the source through. If math renders, that escape round-trips correctly.

## Inline formatting

**Bold**, *italic*, ***both***, ~~strikethrough~~, `code`, and a
[link](https://example.invalid/).

Footnote-style link: [ref][1]

[1]: https://example.invalid/ref

## Images

External, blocked unless allowed in Settings:

![remote](https://example.invalid/image.png)

Broken relative path:

![missing](./does-not-exist.png)

## Long line

This is a deliberately long line to check that horizontal overflow is handled without the whole document gaining a horizontal scrollbar, because the preview pane is narrow and wrapping is what should happen instead.

## Raw HTML

Markdown raw HTML is rendered as markup on purpose, under CSP.

<div style="padding:8px;border:1px solid currentColor;border-radius:4px">
A raw <strong>HTML</strong> block.
</div>

<details><summary>Collapsed section</summary>

Hidden content with a `code` span.

</details>
""")

write("02-markdown/headings-only.md", "\n\n".join(
    [f"{'#' * level} Heading level {level}" for level in range(1, 7)]
    + ["Paragraph after the last heading, to check the final gap."]
) + "\n")

write("02-markdown/lists-deep.md", """\
# Deep nesting

- level 1
  - level 2
    - level 3
      - level 4
        - level 5
- back to level 1

1. one
   1. one.one
      1. one.one.one
2. two

- mixed
  1. ordered inside unordered
  2. second
- back

Term list via GFM table is the only definition-list route:

| term | definition |
|------|------------|
| UTI | Uniform Type Identifier |
""")

write("02-markdown/empty.md", "")
write("02-markdown/whitespace-only.md", "   \n\n\t\n   \n")


# --------------------------------------------------------------------------
# 03 - special characters
#
# Each case targets a specific escaping contract in the source:
#   HTMLEscaper           & < > " '
#   ScriptEscaping.forTemplateLiteral      \\  `  $  </script  <!--
#   ScriptEscaping.forSingleQuotedLiteral  the above plus '  CR LF U+2028 U+2029
#   CSSStringEscaper      \\  "  <  CR LF        (font family only)
# Nothing here should ever execute, break the layout, or truncate the document.
# --------------------------------------------------------------------------

UNICODE_SAMPLER = """\
Latin with diacritics : Ærøskøbing naïve façade Þórshöfn ĳsselmeer
Greek                 : Ψυχή αβγδε ΑΒΓΔΕ
Cyrillic              : Привет мир Ёлка
Korean                : 안녕하세요 한글 자모 ㄱㄴㄷ 읽기
Japanese              : こんにちは カタカナ 漢字 ふりがな
Chinese               : 你好世界 繁體字 简体字
Arabic (RTL)          : مرحبا بالعالم
Hebrew (RTL)          : שלום עולם
Thai (no word breaks) : สวัสดีชาวโลก
Devanagari            : नमस्ते दुनिया
Emoji                 : 😀 🎉 🚀 ✅ ❌ ⚠️
Emoji ZWJ sequence    : 👨‍👩‍👧‍👦 🧑‍🚀 🏳️‍🌈
Emoji skin tone       : 👋🏽 👍🏿
Combining marks       : e◌́ = é  a◌̈ = ä  z̷̧̧̛͇̰a̸l̵g̶o̷
Surrogate pairs       : �examples 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𠜎 𡃁
Math symbols          : ∀x∈ℝ ∃y ≤ ≥ ≠ ≈ ∞ ∑ ∏ √ ∫ ∂
Box drawing           : ┌───┬───┐ │ a │ b │ └───┴───┘
Arrows                : ← → ↔ ⇐ ⇒ ⇔ ↩ ↪
Currency              : $ € £ ¥ ₩ ₿ ¢ ₹
Zero width (invisible): a\u200bb\u200cc\u200dd
Non-breaking space    : a\u00a0b
Soft hyphen           : super\u00adcalifragilistic
Line separator U+2028 : before\u2028after
Para separator U+2029 : before\u2029after
Byte order mark inline: a\ufeffb
Ideographic space     : a\u3000b
"""

ADVERSARIAL_TEXT = """\
HTML metacharacters   : & < > " ' &amp; &lt; &#39; &#x27;
Already-escaped text  : &amp;amp; should stay literally &amp;amp;
Tag-like text         : <b>not bold</b> <img src=x onerror=alert(1)>
Real end tag          : </script> </script > </script/ </SCRIPT>
Not an end tag        : </scriptfoo </scripting </script-tag
Comment opener        : <!-- and a closer --> and a lone <!--
Style end             : </style> </STYLE >
Template literal      : `backtick` ${1+1} ${alert(1)} \\` \\${
Backslashes           : \\ \\\\ \\n \\t \\u0041 C:\\Users\\name
Quotes                : 'single' "double" `back` \u2018smart\u2019 \u201ccurly\u201d
CSS injection shape   : "; } body { display: none } .x {
JS string break       : '; alert(1); //
SQL-ish               : ' OR 1=1 --
Format specifiers     : %s %d %@ %n {0} {} $VAR ${VAR}
Regex metacharacters  : .*+?^$()[]{}|/
Control pictures      : \u2400 \u2401 \u240a
Tab separated\tcolumns\there
"""

write("03-special-chars/unicode.txt", UNICODE_SAMPLER)
write("03-special-chars/adversarial.txt", ADVERSARIAL_TEXT)

write("03-special-chars/unicode.md",
      "# Unicode in markdown\n\nEach line is prose, so it also exercises the\n"
      "font stack and line breaking.\n\n```\n" + UNICODE_SAMPLER + "```\n\n"
      "And inline: 한글, 😀, مرحبا, ∑∫√, `코드 span`.\n\n"
      "| 언어 | 인사 |\n|------|------|\n| 한국어 | 안녕하세요 |\n"
      "| 日本語 | こんにちは |\n| العربية | مرحبا |\n")

write("03-special-chars/adversarial.md", r"""# Adversarial markdown

Nothing here may execute, break the layout, or cut the document short.

## In prose

Backtick and interpolation: `` ` `` and ${1+1} and \${VAR}

A literal end tag in text: </script> — the document must continue past it.

A comment opener: <!-- followed by text that is not a closer

HTML metacharacters: & < > " '

## In a fence

```javascript
var s = "</script>";
var t = `${alert(1)}`;
var u = '\u2028line separator\u2029';
// <!-- comment opener inside code
```

```html
<script>alert('nested script tag in a fence')</script>
<style>body { display: none }</style>
```

## Raw HTML — rendered as markup on purpose, inert under CSP

<script>window.__executed = true;</script>

<img src=x onerror="window.__executed = true">

<a href="javascript:alert(1)">javascript: link</a>

<iframe src="https://example.invalid/"></iframe>

<div onclick="alert(1)">inline handler</div>

If any of the above produced a dialog or blanked the page, the policy failed.
A blocked-image placeholder or an empty gap is the correct outcome.

## Link and image edge cases

[empty target]()

![empty src]()

[fragment](#heading-1)

<https://example.invalid/autolink>

## Tables with pipes

| column | value |
|--------|-------|
| escaped pipe | a \| b |
| code with pipe | `a \| b` |
| html | `<b>` |
""")

write("03-special-chars/adversarial.json", json.dumps({
    "html_metacharacters": "& < > \" '",
    "script_end_tag": "</script>",
    "script_end_variants": ["</script >", "</script/", "</SCRIPT>"],
    "not_an_end_tag": "</scriptfoo",
    "comment_opener": "<!--",
    "style_end": "</style>",
    "template_literal": "`backtick` ${1+1}",
    "backslashes": "\\ \\\\ C:\\Users\\name",
    "quotes": "'single' \"double\"",
    "line_separator": "before\u2028after",
    "para_separator": "before\u2029after",
    "zero_width": "a\u200bb",
    "emoji": "👨‍👩‍👧‍👦 🚀",
    "korean": "안녕하세요",
    "rtl": "مرحبا بالعالم",
    "css_injection": "\"; } body { display: none } .x {",
    "control_chars": "tab\there",
}, indent=2, ensure_ascii=False) + "\n")

write("03-special-chars/adversarial.yaml", """\
html_metacharacters: '& < > " '''
script_end_tag: "</script>"
not_an_end_tag: "</scriptfoo"
comment_opener: "<!--"
style_end: "</style>"
template_literal: "`backtick` ${1+1}"
backslashes: "C:\\\\Users\\\\name"
emoji: "👨‍👩‍👧‍👦 🚀"
korean: 안녕하세요
rtl: "مرحبا بالعالم"
css_injection: '"; } body { display: none } .x {'
colon_in_value: "key: value inside a string"
hash_not_comment: "value # not a comment"
""")

# Encoding and line-ending cases. preparePreviewOfFile tries UTF-8 and then
# ISO-8859-1, so a latin-1 file must render rather than fail.
write("03-special-chars/crlf-line-endings.txt",
      "Every line here ends with CRLF.\r\nSecond line.\r\nThird line.\r\n", newline="")
write("03-special-chars/mixed-line-endings.txt",
      "unix\nwindows\r\nold-mac\rmixed\n", newline="")
write("03-special-chars/latin1.txt",
      "Latin-1, not UTF-8. Café, naïve, Ærø, £5.\n".encode("iso-8859-1"))
write("03-special-chars/utf8-bom.txt",
      "\ufeffThis file starts with a UTF-8 byte order mark.\nSecond line.\n")
write("03-special-chars/no-trailing-newline.txt", "No newline at end of file.")
write("03-special-chars/single-long-line.txt",
      "word " * 12_000 + "\n")
write("03-special-chars/tabs-and-alignment.txt",
      "col1\tcol2\tcol3\n" + "".join(f"r{i}\tvalue{i}\t{'x' * i}\n" for i in range(1, 12)))
write("03-special-chars/control-characters.txt",
      "Bell(\x07) Backspace(\x08) FormFeed(\x0c) Vertical(\x0b) Escape(\x1b) NUL-free\n"
      "Next line after control characters.\n")


# --------------------------------------------------------------------------
# 04 - size limits
#
# PlainTextRenderer.boundedPreview cuts the preview at MAX_UTF16_UNITS units
# or on the MAX_LINES-th newline, whichever comes first, and appends a notice.
# These sit either side of both bounds so the notice can be seen to appear
# exactly when it should -- and, just as importantly, not before.
# --------------------------------------------------------------------------

def json_lines(count):
    """A JSON array of `count` short records, one per line."""
    body = "\n".join(
        f'  {{"i":{i},"ok":{"true" if i % 2 else "false"}}},' for i in range(1, count - 1)
    )
    return "[\n" + body.rstrip(",") + "\n]\n"


# 9,998 newlines: the last line the renderer keeps. No notice expected.
write("04-size-limits/json-9999-lines.json", json_lines(9_999))

# Exactly at the boundary. Useful for seeing which side it falls on.
write("04-size-limits/json-10000-lines.json", json_lines(10_000))

# Well past it. Truncation notice expected, and the gutter should stop with
# the text rather than running on.
write("04-size-limits/json-12000-lines.json", json_lines(12_000))

# The line count is fine but the byte budget is not: ~28 UTF-16 units a line
# over 10k lines passes MAX_UTF16_UNITS first. Notice expected for the *other*
# reason.
write("04-size-limits/json-wide-lines.json", "[\n" + "\n".join(
    f'  {{"i":{i},"payload":"{"x" * 48}"}},' for i in range(1, 9_000)
).rstrip(",") + "\n]\n")

# One enormous line. Tests horizontal overflow rather than line count.
write("04-size-limits/json-one-huge-line.json",
      json.dumps({"blob": "y" * 300_000}) + "\n")

# Non-BMP characters count as 2 UTF-16 units each, which is what the width
# calculation in boundedPreview exists for. 150k emoji = 300k units.
write("04-size-limits/emoji-over-budget.txt", "🚀" * 150_000 + "\n")

# A large log: exercises the log path, the bounded pattern matcher's metering
# and its "highlighting was skipped" notice, all at once.
levels = ["INFO", "DEBUG", "WARN", "ERROR", "INFO", "TRACE", "FATAL", "CRITICAL"]
write("04-size-limits/big.log", "".join(
    f"2026-09-21 10:{i // 60 % 60:02d}:{i % 60:02d} {levels[i % len(levels)]:<8} "
    f"event {i} processed in {i % 997}ms\n"
    for i in range(1, 15_001)
))

write("04-size-limits/deeply-nested.json",
      json.dumps(json.loads("[" * 200 + "]" * 200), indent=1) + "\n")

write("04-size-limits/long.md", "# Long document\n\n" + "\n\n".join(
    f"## Section {i}\n\nParagraph {i} with some prose, `code`, and a "
    f"[link](https://example.invalid/{i})."
    for i in range(1, 501)
) + "\n")


# --------------------------------------------------------------------------
# 05 - regressions: behaviour that must be unchanged
# --------------------------------------------------------------------------

write("05-regression/levels.log", """\
2026-09-21 10:00:01 INFO     Application started successfully
2026-09-21 10:00:02 DEBUG    Loading configuration from /etc/app/config.yaml
2026-09-21 10:00:03 TRACE    Entering RequestHandler.process
2026-09-21 10:00:15 WARN     Slow query detected (2340ms)
2026-09-21 10:00:16 WARNING  Memory usage above 80% threshold (82.3%)
2026-09-21 10:00:30 ERROR    Failed to process request: timeout after 30s
2026-09-21 10:00:45 FATAL    Unrecoverable error: disk full
2026-09-21 10:00:45 CRITICAL Shutting down
2026-09-21 10:00:46 INFO     Not a level: ERRORS ERROR_CODE lowercase error
""")

# ANSI conversion is wired to notebook error tracebacks, not to .log files.
# These escape sequences are expected to show literally. Recorded so the
# behaviour is a known one rather than a surprise.
write("05-regression/ansi-codes.log",
      "\x1b[31mred\x1b[0m \x1b[32mgreen\x1b[0m \x1b[1;33mbold yellow\x1b[0m\n"
      "\x1b[0;31mERROR with colour codes\x1b[0m\n"
      "plain line\n")

write("05-regression/plain.txt", """\
Plain text, deliberately uncoloured.

`txt` is the one file type the shipped default configures with
syntaxHighlight false, so the extension-driven language lookup must not
override it.

    Indented text should preserve its whitespace.

Special characters: <html> & "quotes"
""")

write("05-regression/notebook.ipynb", json.dumps({
    "nbformat": 4, "nbformat_minor": 5,
    "metadata": {"kernelspec": {"display_name": "Python 3",
                                "language": "python", "name": "python3"}},
    "cells": [
        {"cell_type": "markdown", "metadata": {}, "source": [
            "# Notebook\n", "\n",
            "Markdown cells use the same spacing rules as a `.md` document.\n", "\n",
            "- list item\n", "  - nested\n", "\n",
            "> blockquote\n", "\n",
            "Inline math: $E = mc^2$\n", "\n",
            "```json\n", "{\"in\": \"a markdown cell\"}\n", "```\n"]},
        {"cell_type": "code", "execution_count": 1, "metadata": {},
         "source": ["import math\n", "\n",
                    "def area(r: float) -> float:\n",
                    "    return math.pi * r ** 2\n", "\n",
                    "print(area(2))"],
         "outputs": [{"output_type": "stream", "name": "stdout",
                      "text": ["12.566370614359172\n"]}]},
        {"cell_type": "code", "execution_count": 2, "metadata": {},
         "source": ["1 / 0"],
         "outputs": [{"output_type": "error", "ename": "ZeroDivisionError",
                      "evalue": "division by zero",
                      "traceback": [
                          "\u001b[0;31m---------------------------------------------------------------------------\u001b[0m",
                          "\u001b[0;31mZeroDivisionError\u001b[0m                         Traceback (most recent call last)",
                          "\u001b[0;32m<ipython-input-2>\u001b[0m in \u001b[0;36m<module>\u001b[0m\n\u001b[0;32m----> 1\u001b[0;31m 1 / 0\n\u001b[0m",
                          "\u001b[0;31mZeroDivisionError\u001b[0m: division by zero"]}]},
        {"cell_type": "code", "execution_count": 3, "metadata": {},
         "source": ["print('특수문자 & < > \" \\' </script> ${1+1}')"],
         "outputs": [{"output_type": "stream", "name": "stdout",
                      "text": ["특수문자 & < > \" ' </script> ${1+1}\n"]}]},
        {"cell_type": "raw", "metadata": {}, "source": ["A raw cell. & < > stay literal."]},
    ],
}, indent=1) + "\n")


# --------------------------------------------------------------------------
# 06 - source code: always routed, newly coloured
#
# These reach the extension through public.source-code -> public.plain-text
# and always did. What is new is that they resolve a language from the
# extension instead of rendering grey.
# --------------------------------------------------------------------------

SOURCES = {
    "sample.swift": """\
import Foundation

public enum SyntaxLanguage: String, CaseIterable {
    case json, yaml, swift, python

    public var displayName: String {
        switch self {
        case .json: "JSON"
        case .yaml: "YAML"
        case .swift: "Swift"
        case .python: "Python"
        }
    }
}

public struct Preview: Sendable {
    let title: String
    var lineCount = 0

    func render(_ content: String) throws -> String {
        guard !content.isEmpty else { throw PreviewError.empty }
        return content.split(separator: "\\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { "\\($0.offset + 1)\\t\\($0.element)" }
            .joined(separator: "\\n")
    }
}

enum PreviewError: Error { case empty }
""",
    "sample.py": '''\
"""Docstring with 한글 and emoji 🚀."""
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Preview:
    title: str
    tags: list[str] = field(default_factory=list)
    enabled: bool = True

    def render(self, content: str) -> str:
        if not content:
            raise ValueError("empty content")
        return "\\n".join(
            f"{i + 1}\\t{line}" for i, line in enumerate(content.splitlines())
        )


def fib(n: int) -> int:
    return n if n <= 1 else fib(n - 1) + fib(n - 2)


if __name__ == "__main__":
    print(Preview("demo", tags=["a", "b"]).render("x\\ny"))
''',
    "sample.sh": """\
#!/usr/bin/env bash
set -euo pipefail

PROJECT="AllYouNeedQuickLook.xcodeproj"
SCHEME="${1:-Tests}"

if [[ ! -d "$PROJECT" ]]; then
  echo "run xcodegen generate first" >&2
  exit 1
fi

xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \\
  -destination "platform=macOS" 2>&1 | grep -E "Executed|TEST"
""",
    "sample.js": """\
const preview = {
  title: 'demo',
  tags: ['a', 'b'],
  async render(content) {
    if (!content) throw new Error('empty');
    return content.split('\\n').map((line, i) => `${i + 1}\\t${line}`).join('\\n');
  },
};

export default preview;
""",
    "sample.rb": """\
# frozen_string_literal: true
class Preview
  attr_reader :title, :tags

  def initialize(title, tags: [])
    @title = title
    @tags = tags
  end

  def render(content)
    raise ArgumentError, 'empty' if content.empty?
    content.lines.each_with_index.map { |line, i| "#{i + 1}\\t#{line}" }.join
  end
end
""",
    "sample.go": """\
package preview

import (
\t"errors"
\t"fmt"
\t"strings"
)

var ErrEmpty = errors.New("empty content")

type Preview struct {
\tTitle string
\tTags  []string
}

func (p Preview) Render(content string) (string, error) {
\tif content == "" {
\t\treturn "", ErrEmpty
\t}
\tvar b strings.Builder
\tfor i, line := range strings.Split(content, "\\n") {
\t\tfmt.Fprintf(&b, "%d\\t%s\\n", i+1, line)
\t}
\treturn b.String(), nil
}
""",
    "sample.rs": """\
use std::fmt::Write;

#[derive(Debug, Clone)]
pub struct Preview {
    pub title: String,
    pub tags: Vec<String>,
}

impl Preview {
    pub fn render(&self, content: &str) -> Result<String, &'static str> {
        if content.is_empty() {
            return Err("empty content");
        }
        let mut out = String::new();
        for (i, line) in content.lines().enumerate() {
            writeln!(out, "{}\\t{}", i + 1, line).unwrap();
        }
        Ok(out)
    }
}
""",
    "sample.java": """\
package dev.yohanpark.preview;

import java.util.List;
import java.util.stream.IntStream;

public record Preview(String title, List<String> tags) {

    public String render(String content) {
        if (content.isEmpty()) {
            throw new IllegalArgumentException("empty content");
        }
        String[] lines = content.split("\\n", -1);
        return IntStream.range(0, lines.length)
            .mapToObj(i -> (i + 1) + "\\t" + lines[i])
            .reduce((a, b) -> a + "\\n" + b)
            .orElse("");
    }
}
""",
    "sample.sql": """\
-- Aggregates with a CTE and a window function
WITH active AS (
    SELECT id, name, created_at
    FROM users
    WHERE active = TRUE AND created_at >= '2026-01-01'
)
SELECT
    name,
    COUNT(*)                                     AS total,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)   AS rank
FROM active
GROUP BY name
HAVING COUNT(*) > 1
ORDER BY total DESC
LIMIT 20;
""",
    "sample.css": """\
:root {
    --bg: #ffffff;
    --text: #1d1d1f;
}

@media (prefers-color-scheme: dark) {
    :root { --bg: #1d1d1f; --text: #f5f5f7; }
}

.preview {
    background: var(--bg);
    color: var(--text);
    font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
    padding: clamp(8px, 2vw, 24px);
}

.preview :not(pre) > code {
    background: color-mix(in srgb, var(--text) 8%, transparent);
    border-radius: 4px;
}
""",
    "sample.scss": """\
$bg: #ffffff;
$text: #1d1d1f;

@mixin themed($background, $foreground) {
    background: $background;
    color: $foreground;
}

.preview {
    @include themed($bg, $text);

    &__title { font-weight: 600; }
    &--dark { @include themed($text, $bg); }

    pre code { padding: 0; background: transparent; }
}
""",
    "sample.pl": """\
#!/usr/bin/env perl
use strict;
use warnings;

my %tags = (a => 1, b => 2);

sub render {
    my ($content) = @_;
    die "empty content\\n" unless length $content;
    my $i = 0;
    return join "\\n", map { sprintf "%d\\t%s", ++$i, $_ } split /\\n/, $content;
}

print render("x\\ny"), "\\n";
""",
    "sample.lua": """\
local Preview = {}
Preview.__index = Preview

function Preview.new(title, tags)
    return setmetatable({ title = title, tags = tags or {} }, Preview)
end

function Preview:render(content)
    assert(content ~= "", "empty content")
    local out, i = {}, 0
    for line in content:gmatch("[^\\n]*") do
        i = i + 1
        out[#out + 1] = string.format("%d\\t%s", i, line)
    end
    return table.concat(out, "\\n")
end

return Preview
""",
    "Makefile.mk": """\
SCHEME ?= Tests
PROJECT := AllYouNeedQuickLook.xcodeproj

.PHONY: all test build clean

all: test build

$(PROJECT):
\txcodegen generate

test: $(PROJECT)
\txcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination "platform=macOS"

clean:
\trm -rf $(PROJECT)
""",
    "sample.diff": """\
diff --git a/Shared/Renderers/MarkdownRenderer.swift b/Shared/Renderers/MarkdownRenderer.swift
--- a/Shared/Renderers/MarkdownRenderer.swift
+++ b/Shared/Renderers/MarkdownRenderer.swift
@@ -8,6 +8,7 @@ public final class MarkdownRenderer: Renderer {
     public func render(content: String, config: AppConfig, ...) -> String {
+        let resolved = config.resolvedConfig(for: fileExtension)
         let escapedContent = ScriptEscaping.forTemplateLiteral(content)
-        let body = \"\"\"
+        let customCSS = \"\"\"
""",
}

for name, source in SOURCES.items():
    write(f"06-source-code/{name}", source)


# --------------------------------------------------------------------------
# 07 - deliberately not claimed
# --------------------------------------------------------------------------

write("07-not-claimed/sample.xml", """\
<?xml version="1.0" encoding="UTF-8"?>
<!-- public.xml is deliberately absent from QLSupportedContentTypes. -->
<configuration>
  <server host="localhost" port="8080">
    <tls enabled="false" cert="/etc/ssl/cert.pem"/>
  </server>
  <features>
    <feature name="syntaxHighlight" enabled="true"/>
  </features>
</configuration>
""")

write("07-not-claimed/sample.csv",
      "name,status,note\n"
      "Markdown,Supported,this extension\n"
      "JSON,Supported,newly routed\n"
      "\"quoted, with comma\",Supported,\"embedded \"\"quotes\"\"\"\n"
      "한글,Supported,unicode\n")

write("07-not-claimed/sample.ts", """\
// macOS resolves .ts to public.mpeg-2-transport-stream, a MOVIE type --
// not TypeScript. Claiming it would have been a mistake, so this file is
// expected to get a video preview or none at all.
export interface Preview {
  title: string;
  tags: string[];
}
""")

write("07-not-claimed/README.md", """\
# Not claimed on purpose

- **`sample.xml`** — `public.xml` was left to the system preview, as agreed.
- **`sample.csv`** — the awkward one. `public.comma-separated-values-text`
  conforms to `public.plain-text`, so this extension *already* claimed it
  before any of this work. Whichever preview Finder picks, that behaviour is
  unchanged by these fixes and was not part of this round.
- **`sample.ts`** — macOS resolves `.ts` to
  `public.mpeg-2-transport-stream`, a movie type. Expect a video preview or
  nothing.
""")


# --------------------------------------------------------------------------
# 08 - malformed input
# --------------------------------------------------------------------------

write("08-malformed/truncated.json", '{"name": "demo", "unterminated": "value\n')
write("08-malformed/trailing-comma.json", '{\n  "a": 1,\n  "b": 2,\n}\n')
write("08-malformed/not-json-at-all.json", "this is not JSON, it is prose.\n")
write("08-malformed/bad-indent.yaml", "a: 1\n  b: 2\n\tc: 3\n")
write("08-malformed/not-a-notebook.ipynb", '{"nbformat": 4, "cells": "not an array"}\n')
write("08-malformed/unknown-cell-type.ipynb", json.dumps({
    "nbformat": 4, "nbformat_minor": 5, "metadata": {},
    "cells": [{"cell_type": "markdown", "metadata": {}, "source": ["# fine"]},
              {"cell_type": "sql", "metadata": {}, "source": ["SELECT 1"]}],
}, indent=1) + "\n")
write("08-malformed/empty.ipynb", "")
write("08-malformed/unclosed-fence.md", "# Unclosed fence\n\n```json\n{\"a\": 1}\n")


# --------------------------------------------------------------------------
# 11 - sandbox realities: relative images, remote images, Plotly
#
# The relative images are real bytes on purpose: the local-image handler
# refuses anything CGImageSource does not recognise, so placeholder text named
# .png would prove the refusal path and nothing else. Everything stays inside
# 11-sandbox-realities/ because the generator only wipes its destination, so
# "one level above" the document is doc/ -> 11-sandbox-realities/up.png.
# --------------------------------------------------------------------------

def tiny_png(rgb, size=48):
    """A valid size x size solid-colour PNG, standard library only."""
    def chunk(kind, data):
        body = kind + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))
    row = b"\x00" + bytes(rgb) * size
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * size))
            + chunk(b"IEND", b""))


write("11-sandbox-realities/doc/same.png", tiny_png((220, 50, 47)))
write("11-sandbox-realities/doc/sub/in-sub.png", tiny_png((38, 139, 210)))
write("11-sandbox-realities/doc/a b.png", tiny_png((133, 153, 0)))
write("11-sandbox-realities/up.png", tiny_png((181, 137, 0)))
write("11-sandbox-realities/doc/logo.svg", """\
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <circle cx="24" cy="24" r="22" fill="#6c71c4"/>
  <path d="M14 26l7 7 13-16" fill="none" stroke="#fff" stroke-width="5"/>
</svg>
""")
write("11-sandbox-realities/doc/fake.png",
      "This is plain text named .png. It is not an image.\n")

write("11-sandbox-realities/doc/relative-images.md", """\
# Relative images

Each image below is a coloured square or a logo. A broken-image icon or a
missing square is a failure, except the last case, which must be refused.

Same folder: ![same](same.png)

Subfolder: ![in sub](sub/in-sub.png)

Parent folder: ![up](../up.png)

Space in the name, written as `%20`: ![a b](a%20b.png)

SVG: ![logo](logo.svg)

Query string is ignored: ![same again](same.png?v=2)

Not an image (text named .png), must be refused: ![fake](fake.png)

End of document.
""")

write("11-sandbox-realities/remote-image.md", """\
# Remote image

![apple favicon](https://www.apple.com/favicon.ico)

Text after the image. With external images off, the image above must be
replaced by an "External image blocked" placeholder.
""")


def plotly_cell(source, figures, png=None):
    """Plotly output bundle; `png` rides along as the static fallback that
    plotly's own notebook export stores beside the JSON."""
    outputs = []
    for figure in figures:
        data = {"application/vnd.plotly.v1+json": figure,
                "text/plain": ["Figure()"]}
        if png is not None:
            data["image/png"] = base64.b64encode(png).decode("ascii")
        outputs.append({"output_type": "display_data", "metadata": {}, "data": data})
    return {"cell_type": "code", "execution_count": 1, "metadata": {},
            "source": source, "outputs": outputs}


def notebook(cells):
    return json.dumps({
        "nbformat": 4, "nbformat_minor": 5,
        "metadata": {"kernelspec": {"display_name": "Python 3",
                                    "language": "python", "name": "python3"}},
        "cells": cells,
    }, indent=1) + "\n"


PLAIN_FIGURE = {
    "data": [{"type": "scatter", "mode": "lines+markers", "name": "plain arrays",
              "x": [1, 2, 3, 4], "y": [1, 4, 9, 16]}],
    "layout": {"title": {"text": "Figure with plain arrays"}},
}
TYPED_FIGURE = {
    "data": [{"type": "scatter", "mode": "lines+markers", "name": "typed array",
              "x": [1, 2], "y": {"dtype": "f8", "bdata": "AAAAAAAA8D8AAAAAAAAAQA=="}}],
    "layout": {"title": {"text": "Figure with a typed-array y (1.0, 2.0)"}},
}

write("11-sandbox-realities/plotly.ipynb", notebook([
    {"cell_type": "markdown", "metadata": {}, "source": [
        "# Plotly figures\n", "\n",
        "Two charts below. Hover shows values; there is no toolbar, drag or zoom."]},
    plotly_cell(["fig = px.line(x=[1, 2, 3, 4], y=[1, 4, 9, 16])\n", "fig"],
                [PLAIN_FIGURE]),
    plotly_cell(["fig = go.Figure(go.Scatter(x=[1, 2], y=np.array([1.0, 2.0])))\n",
                 "fig"],
                [TYPED_FIGURE], png=tiny_png((108, 113, 196))),
]))

PANDAS_HTML = """\
<div>
<style scoped>
    .dataframe tbody tr th:only-of-type { vertical-align: middle; }
    .dataframe tbody tr th { vertical-align: top; }
    .dataframe thead th { text-align: right; }
</style>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>name</th>
      <th>score</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0</th>
      <td>alpha</td>
      <td>1.5</td>
    </tr>
    <tr>
      <th>1</th>
      <td>beta</td>
      <td>2.5</td>
    </tr>
  </tbody>
</table>
</div>
"""
write("11-sandbox-realities/pandas-table.ipynb", notebook([
    {"cell_type": "code", "execution_count": 1, "metadata": {},
     "source": ["df"],
     "outputs": [{"output_type": "execute_result", "execution_count": 1,
                  "metadata": {},
                  "data": {"text/html": PANDAS_HTML.splitlines(keepends=True),
                           "text/plain": ["  name  score\n0 alpha    1.5\n1  beta    2.5"]}}]},
]))

PLOTLY_HTML_ONLY = """\
<div>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<div id="plotly-html-only" class="plotly-graph-div" style="height:300px;width:400px;"></div>
<script type="text/javascript">
Plotly.newPlot("plotly-html-only", [{"type": "scatter", "x": [1, 2, 3], "y": [3, 1, 2]}], {});
</script>
</div>
"""
write("11-sandbox-realities/plotly-html-only.ipynb", notebook([
    {"cell_type": "code", "execution_count": 1, "metadata": {},
     "source": ["fig.show()"],
     "outputs": [{"output_type": "display_data", "metadata": {},
                  "data": {"text/html": PLOTLY_HTML_ONLY.splitlines(keepends=True)}}]},
]))



# --------------------------------------------------------------------------
# The checklist
# --------------------------------------------------------------------------

write("000-CHECKLIST.md", """\
# Preview verification corpus

Generated by `scripts/make-preview-corpus.py` in the repository. Regenerate
rather than edit by hand — the generator records *why* each file exists.

Preview every file with **Space** in Finder. The host app's Preview tab does
not prove Finder routing; only Space does.

## Before anything else

Run `scripts/install-to-applications.sh --reset-config` in the repository
first. It makes `/Applications/AllYouNeedQuickLook.app` the single registered
copy and clears the stale registrations that otherwise show up as duplicate
rows in System Settings — including ghosts for build directories that no
longer exist.

Then launch the app once, so the system offers the extension, and check it is
enabled in System Settings → General → Login Items & Extensions → Quick Look.

If nothing below behaves, rule those out before suspecting the code. And when
reporting a result, say which copy produced it.

## 01-newly-routed — the reported bug

These previewed as nothing at all before, because `public.json`,
`public.yaml` and `public.toml` conform to `public.text` and never to
`public.plain-text`.

| File | Expect |
|------|--------|
| `basic.json` | Keys, strings, numbers, `true`/`false`/`null` all coloured. Line-number gutter on the left. |
| `basic.yaml` / `basic.yml` | Identical output — both resolve to `public.yaml`. |
| `multi-document.yaml` | Three `---` documents, all coloured. |
| `basic.toml` / `gitconfig-style.cfg` | Coloured. highlight.js has no TOML grammar; `toml` is its own alias for `ini`, so section headers and keys colour but TOML-only syntax is not specially handled. |
| `minified.json` | One long line, horizontally scrollable inside the block. |
| `empty-file.json` | Empty preview, no crash. |

None of these needed anything added in Settings. Adding one there must not
change the result.

## 02-markdown — formatting

`format-check.md` is the main one. Check, in order:

- Headings clear of surrounding text; `h1`/`h2` underlined.
- Lists indented past their bullets; nesting visible at three levels.
- **Blockquote legible in both light and dark mode.** Toggle the system
  appearance. This is the one that used to fail contrast.
- Horizontal rules with space above and below.
- Fenced code in **one** box. A box inside a box in a second colour means the
  nested-background fix did not take.
- `json`/`yaml`/`swift`/`python`/`bash`/`sql`/`diff`/`xml`/`css` fences
  coloured with **no** label.
- `dockerfile`/`terraform`/`scala`/`haskell` fences showing a grey
  `no highlighter for "…"` label with best-effort colour underneath.
- The fence with no language: plain, no label.
- Math rendering. The renderer escapes `$` for a JavaScript template literal,
  so this proves that escape round-trips.
- External image replaced by a blocked placeholder, unless allowed in
  Settings.
- Raw HTML block and `<details>` rendered as markup — that is intentional.

## 03-special-chars — escaping

Nothing in this directory may execute, break the layout, or cut a document
short. Each file targets a specific contract:

| File | Targets |
|------|---------|
| `unicode.*` | CJK, RTL, combining marks, ZWJ emoji, surrogate pairs, zero-width and separator characters. Check RTL runs right-to-left and emoji are not split. |
| `adversarial.txt` / `.json` / `.yaml` | `HTMLEscaper`: `& < > " '`. Must appear literally, never as markup. |
| `adversarial.md` | `ScriptEscaping.forTemplateLiteral`: backtick, `${…}`, `</script`, `<!--`. **The document must continue past every one of them.** A preview that stops mid-file means an escape failed. |
| `adversarial.md` raw HTML section | `<script>`, `onerror`, `javascript:` link, `<iframe>`. A dialog or a blank page means the policy failed; a gap or a placeholder is correct. |
| `crlf-line-endings.txt`, `mixed-line-endings.txt` | Line splitting. Gutter numbers must match visible lines. |
| `latin1.txt` | The ISO-8859-1 fallback in `preparePreviewOfFile`. Must render, not fail. |
| `utf8-bom.txt` | BOM must not appear as a visible glyph. |
| `single-long-line.txt` | Wrapping, not a page-wide horizontal scrollbar. |
| `control-characters.txt` | Must not corrupt the rest of the document. |

## 04-size-limits

`PlainTextRenderer` cuts the preview at 262,144 UTF-16 units or on the
10,000th newline and appends a notice.

| File | Expect |
|------|--------|
| `json-9999-lines.json` | Renders in full. **No** truncation notice. |
| `json-10000-lines.json` | The boundary itself — 10,000 newlines, so it falls on the truncated side by one. Notice expected. |
| `json-12000-lines.json` | Truncation notice. Gutter stops with the text. |
| `json-wide-lines.json` | Truncated on the **byte** budget, not the line count. |
| `json-one-huge-line.json` | One 300 KB line. Truncated; must not hang. |
| `emoji-over-budget.txt` | Non-BMP characters count 2 units each — this is what the width calculation exists for. |
| `big.log` | 15,000 lines, 887 K units — cut on the byte budget before the line budget. Level colours plus, likely, the "highlighting was skipped" notice from the pattern matcher's metering. |
| `deeply-nested.json` | 200 levels. Must not hang. |
| `long.md` | 500 sections. Check scrolling stays smooth. |

Watch for how long each takes. QuickLook re-renders from scratch every time.

## 05-regression — must be unchanged

| File | Expect |
|------|--------|
| `levels.log` | `ERROR`/`FATAL`/`CRITICAL` red, `WARN`/`WARNING` orange, `INFO` blue, `DEBUG`/`TRACE` grey. **The important one:** log files must keep their level patterns and must never be diverted onto the syntax path. The last line checks word boundaries — `ERRORS`, `ERROR_CODE` and lowercase `error` must *not* colour. |
| `ansi-codes.log` | Escape sequences shown literally. ANSI conversion is wired to notebook tracebacks, not to `.log`. Known behaviour, not a defect. |
| `plain.txt` | Uncoloured. May be the *system* preview rather than this extension — both declare `public.plain-text`. Unchanged either way. |
| `notebook.ipynb` | Markdown cell spacing matching a `.md` document, code cells auto-detected, stream output, a coloured ANSI traceback, and a cell whose output contains `</script>` and `${1+1}` literally. |

## 06-source-code — always routed, newly coloured

Source code always reached the extension via
`public.source-code → public.plain-text`. What is new is that it resolves a
language automatically instead of rendering grey. All of
`swift py sh js rb go rs java sql css scss pl lua mk diff` should be
coloured.

## 07-not-claimed — control group

See that directory's `README.md`. `sample.ts` is the trap worth seeing: macOS
resolves `.ts` to a movie type.

## 08-malformed — must fail gracefully

No crash, no blank window, no spinner that never ends. A readable error or
plain unhighlighted text is the correct outcome.

`unknown-cell-type.ipynb` is a known limitation: an unrecognised `cell_type`
currently fails the whole notebook rather than the one cell.

## 11-sandbox-realities — local images, remote images, Plotly

Check every case with external images **off** (the default), then **on**
(Settings → toggle → Save), in light and dark appearance. Remote images are
the only thing the toggle changes; local images and Plotly must not depend on it.

| File | Expect |
|------|--------|
| `doc/relative-images.md` | Six images render: `same.png` (red square), `sub/in-sub.png` (blue), `../up.png` (yellow, one folder above `doc/`), `a%20b.png` (green, file is `a b.png`), `logo.svg` (purple circle with a check), and `same.png?v=2` (the red square again, query string ignored). `fake.png` (plain text named .png) is refused: the image is replaced by a placeholder reading "Image unavailable" — never an image and never its text. Same result with external images on or off. |
| `remote-image.md` | External images **off**: an "External image blocked…" placeholder where the image would be. External images **on**: the Apple favicon appears. With no network and images on: a placeholder after the timeout, not a permanently broken icon. |
| `plotly.ipynb` | Two charts. First: a line with four points (1, 4, 9, 16). Second: two points (1.0, 2.0) read from a typed array; its stored `image/png` fallback (a purple square) stays hidden, so no square appears. Hover shows values; no toolbar, no drag, no zoom, no double-click reset. Dark appearance keeps each figure's own colours. The first preview may take a moment (plotly.js is inlined). |
| `pandas-table.ipynb` | A two-row table (`alpha`/`1.5`, `beta`/`2.5`) with an index column, styled like the other notebook output. No script runs. |
| `plotly-html-only.ipynb` | No chart. The HTML output is shown (an empty chart area, about 300 px tall) and the "inline script, not run" notice follows it; nothing loads from `cdn.plot.ly`. Same on or off. |

## Reporting back

Worth saying which of the three layers failed, because they fail in different
places:

1. **Nothing renders, or the system preview appears** → routing: the
   `Info.plist` content types, or extension registration.
2. **Renders but uncoloured** → language resolution.
3. **Renders and coloured but laid out wrong** → the template CSS.
""")


# --------------------------------------------------------------------------

def main():
    total = sum(1 for _ in DEST.rglob("*") if _.is_file())
    size = sum(f.stat().st_size for f in DEST.rglob("*") if f.is_file())
    print(f"corpus written to {DEST}")
    print(f"{total} files, {size / 1_048_576:.1f} MiB")


main()
