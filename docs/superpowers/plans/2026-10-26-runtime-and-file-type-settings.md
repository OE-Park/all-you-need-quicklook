# Runtime integration and file type settings

Goal: complete the existing Tasks 10–17 and make Finder routing limitations visible in Settings, with a working System Settings action.

Architecture: retain the SwiftUI/Shared/Quick Look design; reuse the same repository's runtime at fixed source commit 7c75faf (separate DevTools checkout) rather than repeat known rendering, CSP and sandbox failures. Original local files are backed up under build/before-runtime-integration-20261026. Existing untracked Notebook files are included in that backup. This is code reuse, not evidence of local validation.

User decisions: implement and test in the DevFolder checkout; computer UI verification; randomized test .app names; inspect and optionally remove prior test copies; shared sample corpus under Projects/TEST_SAMPLES.

Ruling: the original spec claim that every added extension is immediately covered by public.plain-text contradicts the actual UTType tree and Apple's QLSupportedContentTypes registration contract. Settings changes rendering preferences only. Declare JSON/YAML/TOML explicitly, explain unsupported types, and expose System Settings > General > Login Items & Extensions > Quick Look. That screen enables extensions; it does not add file types or guarantee a selected provider.

## Tasks

1. Integrate runtime, vendored libraries, host views, extension entry and regression tests from fixed commit. Preserve original local source backup; regenerate and run tests and host build in this checkout.
2. RED: tests for extension normalization, YAML support, unsupported XML/dynamic type, duplicate add preserving overrides and invalid extension rejection. GREEN: a shared FileTypeSupport model reads the bundled extension's declared types, resolves UTType and reports eligible/unsupported/unknown. New Settings rows show status; add/save report persistence; add saves immediately. Welcome and Settings use a shared SystemSettings opener with visible manual navigation fallback.
3. Build harness: inspect known test .apps without touching the installed production app; build a randomized .app with unique host/extension/framework identifiers and isolated config namespace. No automatic global registration cleanup or production-config reset. Script has a --build-only path for computer-tool launch. Keep evidence in build/.
4. Full tests plus build; live WKWebView assertions for Markdown/notebook/local images/Plotly; computer-test Settings add/save, unsupported type feedback, Preview and System Settings button. Finder Space checks require explicit attribution to the test extension using runtime logging/registration evidence. Record any unresolved routing separately.
5. Review diff, update README and validation report, record daily session. No automatic commit or push.
