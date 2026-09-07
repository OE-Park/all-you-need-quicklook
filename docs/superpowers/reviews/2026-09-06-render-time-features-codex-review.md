# Render-time features — Codex local design review

검토일: 2026-09-06. 판정: **현 설계 그대로 구현 착수 불가. 패턴 실행·매칭 단위를 재검토하고 아래 변경 반영 필요.**

## 검토 대상과 근거

- Worktree: `/Users/yohanpark/DevTools/all-you-need-quicklook/.worktrees/feat-render-time-features`
- Branch: `feat/render-time-features`
- HEAD 및 원격 `refs/heads/feat/render-time-features`: `dc9bf1bbf59c48fe67ae7a2236ec9df22c29a2fe`
- 원격 확인: `git ls-remote origin refs/heads/feat/render-time-features`, 성공.
- **로컬 미커밋 변경을 포함한 문서**를 검토했다. 시작 시 변경 파일 8개: `AGENTS.md`, `.github/agents/macos-swift.agent.md`, `.github/copilot-instructions.md`, `.github/instructions/swift.instructions.md`, `.github/pull_request_template.md`, 원래 구현 계획, 이번 설계, 리뷰 프롬프트. 해당 변경은 보존했다.
- 설계 SHA-256: `2fff1ca2a6543a4b07423f04fd3834b1c0dcf8b4c1d44dcb127ea86ba2e58919`
- 프롬프트 SHA-256: `d324aadbd7c9cb7a72297c7a94e66e747813e874e7c76106f8e6353419e4e9e6`
- 설계, 리뷰 프롬프트, 워크트리 지침, renderer 5개, config/notebook schema, ConfigLoader, PreviewWebView, 번들 JS/CSS·기본 설정, SettingsView, 관련 테스트 assertion을 대조했다.
- 아래 설계 줄 번호는 `docs/superpowers/specs/2026-09-06-render-time-features-design.md` 기준이다.

## 전제 검증

| 설계의 기존 결함 주장 | 확인 결과 |
|---|---|
| Notebook markdown fence의 `marked.highlight` 옵션 무시 | 유효. `NotebookRenderer.swift:31`의 옵션이 남아 있고 후속 highlight 대상은 `:46`의 `.code-source code`뿐이다. 번들 v15.0.12를 실제 WebKit에서 실행했을 때 callback 호출 0회, fence에 token span 없음. |
| Notebook metadata 유실 및 code cell 언어 class 부재 | 유효. `NotebookSchema.swift:16`은 metadata를 읽지 않고 `:28`은 빈 dictionary를 쓴다. `NotebookRenderer.swift`의 code cell은 bare `<code>`다. |
| 기본 `.log.syntaxHighlight = true`가 도달 불가 | 유효. `PlainTextRenderer.swift:21`은 언어도 요구하지만 기본 log 설정에는 언어가 없다. |

버전 설명은 정정해야 한다. `highlight` 옵션 제거는 v5가 아니라 **v8.0.0**이다. 번들 v15에서 해당 결함이 발생한다는 결론은 유지된다. 근거: [marked 공식 Old Options](https://github.com/markedjs/marked/blob/master/docs/USING_ADVANCED.md#old-options). 기존 코드 주석에도 같은 버전 오류가 있다.

## Findings

### 1. Critical — 유효한 정규식의 실행 비용을 제한하지 않는다

**Where:** 설계 222–229, 252–256행, Pattern emphasis / Settings.

**The defect:** 컴파일 `try/catch`만으로는 유효하지만 과도하게 backtracking하는 패턴이 WebContent 실행을 장시간 점유하는 것을 막지 못한다.

**The failure:** 설정에 `(a+)+$`, 파일에 `a` 26개 뒤 `!`를 둔다. 실제 WKWebView의 `RegExp.test` 한 번이 약 245ms를 소비했다. 동일한 텍스트 노드를 여러 개 가진 notebook/markdown에서 순차 수행하면 비용이 누적되고, 해당 pass 동안 렌더링과 다른 JS 처리가 지연된다. 18/22/26개의 `a`로 측정한 비용은 3/27/245ms였다. 모두 정상 컴파일하며 false를 반환하므로 malformed-regex 처리는 관여하지 않는다. OS 전체나 Finder 프로세스가 반드시 정지한다는 주장은 하지 않는다.

**Required change:** 실행 비용을 제한하는 명시적 계약 필요. 허용 문법을 제한하는 엔진 또는 실제 중단 가능한 격리 실행과 시간·입력·일치 수 예산을 설계해야 한다. 동일 JS thread의 `setTimeout`만으로 진행 중인 match를 끊을 수 있다고 가정하면 안 된다. 기존 nonce/CSP를 유지하는 실행 방식을 검증해야 한다. 빈 문자열/zero-width match의 진행 규칙도 정해야 한다.

### 2. High — gutter에 줄바꿈 보존과 실제 code와의 정렬 규칙이 없다

**Where:** 설계 189–213행; `Shared/Renderers/HTMLTemplate.swift:60`, `:67`, `:70`, `:95`; `Shared/Resources/css/highlight-light.min.css:1`.

**The defect:** 제시한 `<span>` gutter는 줄바꿈을 접고, font·line-height·상단 padding도 code와 다르게 계산된다.

**The failure:** 설계의 3줄 gutter와 grid를 현재 HTMLTemplate에 넣고 python code를 highlight했다. gutter의 `white-space`는 `normal`, 숫자 1/2/3의 y 좌표는 모두 27px였다. code 첫 글자는 y=55px였다. gutter는 body의 16px/25.6px sans-serif, code는 13px/19.5px monospace이며 theme의 `pre code.hljs`에는 13px padding도 붙었다. 현재 plain-text 사용자 font 설정 역시 `pre.plaintext-content`에만 적용된다. 같은 부모라는 이유로 같은 metric을 상속한다는 논증은 성립하지 않는다.

**Required change:** gutter의 `white-space`, 공유 typography, pre와 theme code의 padding, notebook output의 padding 예외를 함께 정해야 한다. 숫자 개수뿐 아니라 각 줄의 baseline/좌표와 긴 줄의 스크롤을 확인해야 한다. 빈 파일·마지막 개행·CRLF의 줄 수 정의도 필요하다.

### 3. High — text node 단위 매칭은 문서의 문자열 의미를 보존하지 못한다

**Where:** 설계 215–232행.

**The defect:** 각 text node에서 독립적으로 regex를 실행하면 highlighting이 만든 경계에서 일치가 끊기고 기존 log의 줄 단위 anchor 의미도 달라진다.

**The failure:** python `import os`는 실제 highlight 후 `"import"`, `" os\n"` 두 node로 나뉜다. `/import os/`는 code의 합친 textContent에는 일치하지만 각 node에는 일치하지 않는다. `foo **bar**` 같은 markdown의 inline markup 경계도 같다. 또한 기존 log 패턴 `^ERROR`는 두 ERROR 줄에 각각 적용되지만 합친 하나의 node에 flags 없는 `RegExp`를 적용하면 첫 줄만 일치한다. 두 사례 모두 ICU와 JS의 공통 문법이므로 dialect 변경 안내만으로 설명되지 않는다.

**Required change:** 논리적 검색 단위(예: code block 또는 log의 각 줄)를 먼저 정하고 원본 텍스트의 match offset을 기존 DOM text node 범위에 매핑해야 한다. 래핑은 text node만 변경하면서도 매칭은 span 경계에 의존하지 않도록 설계한다. flags, 겹치는 패턴 우선순위, log와 일반 강조의 중복 처리도 명시한다.

### 4. High — skip list가 SVG·MathML·KaTeX 내부를 포함하지 않는다

**Where:** 설계 142–147, 222–225행; `NotebookRenderer.swift`의 `text/html` output 경로.

**The defect:** 허용된 raw HTML의 SVG/MathML과 KaTeX가 만든 구조에도 일반 HTML 강조 요소를 삽입하게 된다.

**The failure:** notebook HTML output의 `<svg><text x="0" y="25">ERROR</text></svg>`에 패턴 `ERROR`를 적용해 text node를 HTML `<mark>` fragment로 교체했다. 실제 WKWebView에서 SVG text의 bbox 폭이 50.3125px에서 0px로 줄었다. DOM textContent는 여전히 `ERROR`라 텍스트 보존 검사로는 실패를 못 잡는다. KaTeX `x^2`의 경우 동일 skip list가 MathML `mi`, TeX `annotation`, 시각용 `span`의 x를 모두 처리 대상으로 남기는 것도 확인했다. KaTeX 래핑 후 시각 품질 자체는 이번에 측정하지 않았다.

**Required change:** `.katex` 및 비-HTML namespace subtree를 건너뛰거나 각 구조에 맞는 별도 강조 규칙을 정의한다. raw HTML 지원을 escape로 제거하지 말고 지원 markup을 보존해야 한다. TreeWalker 변이 중 새로 삽입한 강조 node를 재방문하는 문제도 방지한다.

### 5. High — 번들 log 기본값 수정은 기존 저장 설정에 적용되지 않는다

**Where:** 설계 76–81, 162–169행; `Shared/Config/ConfigLoader.swift:23`.

**The defect:** 구 설정의 값을 유지하면서 `highlightAuto` fallback을 추가하므로 저장된 기존 log 설정은 새 번들 기본값과 다른 동작으로 바뀐다.

**The failure:** 기존 앱에서 font 크기만 바꾸고 Save한 사용자의 config에는 여전히 `log.syntaxHighlight=true`, 언어 없음이 저장된다. 새 버전에서 해당 JSON의 decode가 성공하면 ConfigLoader는 번들 기본값을 사용하지 않는다. 따라서 새 fallback은 log를 자동 추측해 colorize한다. 설계가 방지하려고 한 level 색상과의 충돌이 기존 사용자에게 그대로 생기며, “does not change rendering”은 신규 기본 설정에만 해당한다.

**Required change:** migration 없이 유지할 legacy log 동작과 명시적인 자동 추측 선택을 구분할 규칙을 정하거나 이 동작 변경을 승인된 요구사항으로 명시한다. 새 번들 JSON뿐 아니라 구 번들 값을 저장한 JSON fixture로 로딩 이후의 렌더링을 검증한다.

### 6. High — notebook의 미지원 언어에는 자동 추측도 적용되지 않는다

**Where:** 설계 178–185, 265, 289행.

**The defect:** metadata 언어를 무조건 `language-<lang>`으로 넣지만 번들 highlight.js가 그 언어를 지원하지 않을 때의 처리가 없다.

**The failure:** `metadata.language_info.name="julia"`인 notebook은 현재 번들 36개 언어 목록에 Julia가 없는데도 `language-julia`를 받는다. 실제 `hljs.highlightElement` 실행 결과 class는 `language-julia` 그대로였고 `.hljs`도 token도 생기지 않았다. bare code의 auto 경로와 달리 미지원 explicit class는 highlight를 건너뛴다. 설계의 fallback은 metadata가 없는 경우만 다룬다.

**Required change:** config·metadata·alias·missing/unknown language의 resolution 순서를 명시하고, 번들 `hljs.getLanguage` 결과에 따라 안전한 plain-text 또는 auto 동작을 선택한다. 새 UTType이나 언어 번들 확장은 이 수정에 필요하지 않다. [highlight.js 공식 API](https://highlightjs.readthedocs.io/en/latest/api.html#highlightelement)는 기본 auto 감지와 class로 지정한 언어의 구분을 설명한다. 미지원 Julia의 결과는 로컬 번들 실행으로 검증했다.

### 7. Medium — 제안한 핵심 assertion은 강조 누락과 gutter 붕괴에도 통과한다

**Where:** 설계 270–276행.

**The defect:** hljs class 존재와 gutter 숫자 개수는 강조 적용이나 실제 줄 정렬을 보장하지 않는다.

**The failure:** finding 3의 `import os`는 강조가 0건이어도 hljs span이 남아 있으므로 지정된 assertion을 통과한다. finding 2의 gutter는 숫자 3개와 개행 2개를 보존한 채 한 줄에 그려지므로 textContent 기반 개수 검사도 통과한다. invalid-regex 테스트가 간단한 단일 node의 다른 pattern만 검사하면 이 두 결함과 양립한다. 단순 no-op 변형을 잡는 것은 필요한 조건이지만 span 경계 오류를 잡는 충분조건은 아니다.

**Required change:** expected match의 개수·정확한 텍스트·위치, code 원문 보존, 실제 glyph baseline/좌표, SVG/math 보존을 확인한다. 세 기존 defect 각각에도 notebook markdown fence의 token, metadata 언어 선택, 구 log config 동작을 직접 assert해야 한다. 새로운 기능과 변형 구현은 미구현이므로 이 테스트들을 실행했다고 주장하지 않는다.

## 추가 계약 점검

- **Config 정방향:** 현재 유효한 구 AppConfig는 필수 `version`, `global`과 기존 GlobalConfig 필드를 이미 갖는다. 새 global 필드의 `decodeIfPresent` 기본값과 FileTypeConfig의 새 Optional 필드를 정확히 추가하면 해당 구 입력은 유지 가능하다. ResolvedFileTypeConfig는 Codable 경로가 아니다. 임의로 필수 기존 필드가 빠진 파일까지 구버전 호환 대상으로 주장할 근거는 없다.
- **Config 역방향:** 구 코드로 새 키가 있는 JSON을 decode→encode한 실험에서 `syntaxTheme`, `highlightPatterns`가 사라졌다. 구 실행 파일의 Save는 알 수 없는 키를 보존하지 않는다. downgrade 후 재저장까지 보장하는 요구는 현재 명시되어 있지 않으므로 별도 severity finding으로 승격하지 않았지만, version 1 유지가 양방향 무손실을 의미하지는 않는다.
- **ScriptEscaping:** 현재 API는 template-literal과 single-quoted string용뿐이다. JSON literal용 직렬화·script-boundary 보호 API를 추가해야 하며 기존 문자열 escaper에 직렬화 JSON을 넣으면 안 된다. 테스트는 JS에서 실제 값을 역으로 읽어 비교하고 `</script>`, `<!--`, `<script`, backslash, quote를 포함해야 한다.
- **Pass order:** 생성된 DOM → math → highlight → gutter → pattern의 큰 순서는 기존 highlight 결과 덮어쓰기를 피한다. 그러나 순서만으로 namespace·검색 단위·레이아웃 문제는 해결되지 않는다. 기존 markdown math 함수가 전체 innerHTML을 regex 치환하는 것까지 새 설계가 해결했다는 주장도 하지 않는다.
- **Notebook round trip:** 기존 NotebookSchemaTests에는 metadata round-trip assertion이 없다. 설계 185행의 “round-trip tests keep passing”을 현재 metadata 보존의 근거로 사용할 수 없다. 새 metadata의 missing/partial 객체와 보존 범위를 별도 fixture로 명시해야 한다.

## 실행 검증

환경: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), arm64.

| 구분 | 실행 결과와 범위 |
|---|---|
| 원격 push 확인 | 원격 branch와 HEAD의 전체 SHA 일치 |
| XcodeGen | `xcodegen generate` 성공 |
| 기존 테스트 | `xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-review-20260906 -resultBundlePath /private/tmp/aynql-review-20260906-tests-retry.xcresult` 성공, **107 tests / 0 failures** |
| 기존 live DOM 테스트 | 위 실행에 `PreviewWebViewLiveTests` **16 tests / 0 failures** 포함. 기존 CSP·번들 실행·markdown highlight 등에 대한 assertion 범위만 증명 |
| 호스트·확장 build | `xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination 'platform=macOS' -derivedDataPath /private/tmp/aynql-review-20260906 build` 성공. 기존 ad-hoc signing 단계 포함 |
| 설계 가정 실험 | 기존 Shared.framework의 PreviewWebView/HTMLTemplate와 번들 JS로 임시 Swift 실행 파일 작성·실행. find 1–4, 6의 수치·DOM 결과 및 구 schema의 새 키 소실 관찰 |
| 시각 확인 | screenshot/육안 확인 미실행. bbox·computed style·Range 좌표는 DOM geometry 관찰임 |
| Finder Space | 이번 세션 미실행. 새 기능은 미구현이므로 extension 등록·routing 또는 새 기능의 Finder 완료 판정 없음 |
| 새 기능 테스트·mutation test | 미실행: 해당 구현 자체가 없음 |

첫 테스트 시도는 컴파일 후 macOS `testmanagerd` 접근이 sandbox restriction으로 막혀 exit 65였다. 권한 확장 후 같은 대상의 테스트를 재실행하여 성공했다. 이 환경 오류를 소스 결함이나 macOS 플랫폼 제한으로 취급하지 않았다. 이번 원인은 즉시 드러난 일반 sandbox 권한 문제여서 별도의 장기 개발 함정 노트는 만들지 않았다.

로컬 실행 자료:

- `/private/tmp/aynql-review-20260906-tests-retry.log`
- `/private/tmp/aynql-review-20260906-tests-retry.xcresult`
- `/private/tmp/aynql-review-20260906-build.log`
- `/private/tmp/aynql-review-probe.swift`
- `/private/tmp/aynql-review-probe.log`

임시 실험은 새 기능의 구현이나 회귀 테스트가 아니다. 설계에 적힌 알고리즘 일부와 기존 renderer를 결합해 실패 가정을 확인한 재현 자료다. 기존 소스·설계·사용자 설정은 수정하지 않았다.

## 결론

Critical 1개, High 5개, Medium 1개다. 네 가지 파일 형식과 gutter 방식이라는 제품 결정은 유지할 수 있지만, 패턴의 실행 제한과 논리적 매칭 단위는 구현 계획 전에 재검토해야 한다. 나머지 레이아웃·namespace·저장 설정·언어 fallback·검증 기준을 함께 반영한 뒤 구현에 들어갈 수 있다. 기존 테스트 107개와 호스트 빌드 성공은 현재 기반 코드의 실행 근거이며, 이 설계가 그대로 구현 가능한 상태라는 근거는 아니다.
