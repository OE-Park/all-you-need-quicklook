---
applyTo: "**/*.swift"
---

- Swift 6, `Sendable` where the existing models already use it.
- Public API in `Shared/` stays `public`. Extension and host app types stay internal.
- Follow `AGENTS.md` for destination-specific escaping and intentional raw-HTML paths. `ANSIConverter.escapeHTML` is private; `toHTML()` also interprets ANSI and is not a general-purpose escaper. Reuse an accessible helper with the required semantics, or introduce one within the assigned task.
- Inline JS data requires the matching literal/JSON encoding and script-boundary protection; HTML escaping alone is insufficient.
- Do not reach for SwiftUI in `Shared/` or the QuickLook extension. WebKit/AppKit only there.
- Tests import `@testable import Shared` and stay deterministic (temp directories, no network).
- Match the existing file header comment style and the plan's type names exactly (`AppConfig`, `Notebook`, `CellOutput`, `Renderer`).
