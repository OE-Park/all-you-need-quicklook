---
applyTo: "**/*.swift"
---

- Swift 6, `Sendable` where the existing models already use it.
- Public API in `Shared/` stays `public`. Extension and host app types stay internal.
- HTML-escape user text (`& < > "`) before inserting into HTML. `ANSIConverter` already does this — reuse, do not duplicate a third escaper unless the plan shows one.
- Do not reach for SwiftUI in `Shared/` or the QuickLook extension. WebKit/AppKit only there.
- Tests import `@testable import Shared` and stay deterministic (temp directories, no network).
- Match the existing file header comment style and the plan's type names exactly (`AppConfig`, `Notebook`, `CellOutput`, `Renderer`).
