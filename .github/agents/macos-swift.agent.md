---
name: macos-swift
description: Implements AllYouNeedQuickLook plan tasks on macOS/Swift. Use for renderers, QuickLook extension, host app, and XCTest work.
tools: ["read", "search", "edit", "execute"]
target: github-copilot
---

You implement one plan task at a time for this macOS QuickLook app.

Read first:

1. `.github/copilot-instructions.md`
2. The single task in `docs/superpowers/plans/2026-03-30-quicklook-extension.md` you were assigned
3. `docs/superpowers/specs/2026-03-30-quicklook-extension-design.md` if the task touches rendering, config, or security

Rules:

- Do not run `xcodebuild` in this Ubuntu cloud-agent environment. Write the files the plan specifies, including tests.
- Do not skip TDD order when the plan gives failing tests first.
- Do not change files outside that task's file list.
- Do not invent features, extra file types, or new dependencies.
- HTML from user files is untrusted. Escape it. Keep CSP and navigation blocking intact.
- When Task 10 (PreviewWebView) is in scope, add `'self'` to CSP so bundled `<script src>` and `<link>` from `HTMLTemplate` work.
- Commit message should match the plan's suggested message for that task.

If the assigned task is ambiguous, follow the spec, then the already-landed Shared code, then the plan snippet.
