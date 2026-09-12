# 현재 코드 버그 점검 — 2026-09-12

## 대상과 결론

- 대상: `/Users/yohanpark/DevTools/all-you-need-quicklook`, `main`, `139e07fe725ae110357fa4b7782654620d642a5f`.
- 시작 시 미추적 파일: `asdf.ipynb`, 9월 9일 검토 보고서 및 재현 자료 디렉터리. 기존 파일 보존, 사용자 노트북은 검토 입력으로 사용하지 않음.
- 환경: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), arm64.
- 기능·성능 문제 9건과 이미지 목적지 정책 문제 1건 확인. 수정하지 않음.
- 9월 9일 보고서의 8건을 현재 소스와 다시 대조. DOM/성능/오프라인 이미지 probe 재실행, 설정 이벤트·timeout 전달은 소스로 확인. 폰트 설정 무시와 로그 패턴의 엔티티 손상은 이번에 추가 재현.
- 검사 범위: 호스트 설정/Preview, 확장 입력·라우팅, Shared 렌더러·스키마·WebView·리소스 정책, 관련 테스트. 미연결 bounded compiler/matcher는 기존 41개 테스트 실행 범위만 확인; 이번에 별도 퍼징하지 않음.

## 발견 사항

### 1. P1 — 특정 문서 입력으로 Markdown·문법 강조 평문이 빈 화면

위치: [ScriptEscaping.swift:63](../../Shared/Renderers/ScriptEscaping.swift#L63).

`</script`만 중화하고 `<!--`는 남긴다. `<!--<script>`가 문서 데이터에 포함되면 HTML 토크나이저의 double-escaped 상태 때문에 앱의 script 종료 경계가 깨진다. 번들 JS용 helper에는 이 방어가 있지만 문서용 helper에는 없다.

현재 Shared를 사용하는 실제 WKWebView에서 정상 대조군은 `Control` 제목과 `quicklookReady=true`. 문제 입력은 로딩 상태가 `complete`인데 제목/코드 결과가 null이고 ready도 없다. Markdown과 `syntaxLanguage=plaintext` 양쪽에서 재현. XSS 실행을 입증한 결과는 아니다.

수정 방향: JS 문자열 의미를 유지하며 HTML script 시작/종료 경계를 공통 helper에서 중화하고 두 렌더러의 DOM 원문 보존을 회귀 검증.

### 2. P1 — 기본 로그 강조가 긴 한 줄에서 이차 비용 발생

위치: [PlainTextRenderer.swift:70](../../Shared/Renderers/PlainTextRenderer.swift#L70).

매치마다 계속 커지는 문자열 전체를 `replacingCharacters`로 복사한다. 별도 설정 없이 기본 `.log` 패턴과 한 줄의 `ERROR ` 반복으로 도달한다. 이번 실행의 입력 96/192/384 KB에 각각 0.083/0.346/1.352초 소요. 입력 두 배에 시간이 약 네 배 증가한다. 확장은 크기 제한 없이 파일을 읽고 동기 렌더링하며 이 경로에는 매치·출력·작업 예산이 없다. 더 큰 입력의 장시간 정지는 유도하지 않음.

수정 방향: 원문 구간을 한 번의 순방향 순회로 조합하고 입력·매치·출력 한도와 취소 처리 적용. 현재 번들된 bounded matcher는 이 경로와 미연결이므로 방어 근거가 아니다.

### 3. P2 — 수식 렌더링이 코드 블록 원문을 변경

위치: [MarkdownRenderer.swift:39](../../Shared/Renderers/MarkdownRenderer.swift#L39), [NotebookRenderer.swift:48](../../Shared/Renderers/NotebookRenderer.swift#L48).

DOM의 코드 제외 경계 없이 `innerHTML` 전체에 달러 수식 정규식을 적용한다. Markdown fenced shell 코드 `echo '$HOME$'`의 실제 `pre code.textContent`가 `echo 'HOMEHOMEHOME'`로 바뀜. 노트북에도 같은 HTML 치환 경로가 존재하지만 이번 실행에서 노트북 수식 사례는 별도 재현하지 않음.

수정 방향: 코드·pre 등 제외 구역을 지키는 텍스트 노드 수식 처리.

### 4. P2 — 노트북 Markdown에 엔티티가 그대로 표시됨

위치: [NotebookRenderer.swift:32](../../Shared/Renderers/NotebookRenderer.swift#L32).

Swift에서 HTML 이스케이프한 원문을 `el.innerHTML`로 읽어 marked에 전달한다. 실제 DOM에서 인라인 코드 `a < b & c`가 `a &lt; b &amp; c`로 표시되고 `<b>bold</b>`는 굵은 요소가 아니라 태그 문자로 표시됨.

수정 방향: 초기 컨테이너의 `textContent`에서 원문을 복원한 뒤 Markdown 파싱. 지원되는 raw HTML과 CSP/nonce 계약 유지.

### 5. P2 — 문법 강조를 켜면 줄번호 설정 무시

위치: [PlainTextRenderer.swift:42](../../Shared/Renderers/PlainTextRenderer.swift#L42).

`showLineNumbers=true`, `syntaxHighlight=true`, `syntaxLanguage=plaintext`로 두 줄을 렌더링해도 실제 DOM `.line-number`는 0개. 강조 분기에서 `resolved.showLineNumbers`를 사용하지 않음.

수정 방향: 강조 결과와 독립적인 줄번호 생성 및 켜기/끄기 DOM 검증.

### 6. P2 — 문법 강조를 켜면 지정 폰트가 실제 코드에 적용되지 않음 (추가)

위치: [PlainTextRenderer.swift:13](../../Shared/Renderers/PlainTextRenderer.swift#L13), [HTMLTemplate.swift:68](../../Shared/Renderers/HTMLTemplate.swift#L68).

사용자 폰트는 `pre`에만 적용하고 자식 `code`에는 템플릿의 명시적 SF Mono 선언이 남는다. `fontFamily=Courier`, `syntaxLanguage=plaintext`로 검증한 computed style은 pre가 `Courier, monospace`, 실제 텍스트를 담는 code가 `SF Mono, SFMono-Regular, Menlo, Consolas, monospace`다.

수정 방향: 평문 강조 code에도 사용자 폰트 적용 또는 상속 설정. HTML에 폰트 이름이 포함되는지만 검사하는 기존 테스트로는 잡히지 않음.

### 7. P2 — 사용자 로그 패턴이 HTML 엔티티를 끊어 원문 변형 (추가)

위치: [PlainTextRenderer.swift:28](../../Shared/Renderers/PlainTextRenderer.swift#L28), [PlainTextRenderer.swift:71](../../Shared/Renderers/PlainTextRenderer.swift#L71).

원문이 아니라 이미 이스케이프한 HTML에 패턴을 적용한다. `logLevelPatterns={"error":"&"}`로 `a < b & c`를 렌더링하면 `&lt;`와 `&amp;` 중간에 span이 삽입돼 실제 표시 텍스트가 `a &lt; b &amp; c`로 변한다. 기본 패턴의 문제가 아니라 지원되는 사용자 JSON 패턴에서 발생하는 문제다. 후속 패턴은 앞서 생성한 HTML도 대상으로 삼으므로 원문 범위 기반 처리로 바꿔야 한다.

수정 방향: 원문에서 매치 범위를 계산한 뒤 각 구간을 이스케이프해 HTML 조합. 후속 패턴이 생성된 마크업을 다시 검색하지 않게 처리.

### 8. P2 — Settings 저장 후 선택된 Preview가 갱신되지 않음

위치: [PreviewView.swift:62](../../AllYouNeedQuickLook/Views/PreviewView.swift#L62), [SettingsView.swift:127](../../AllYouNeedQuickLook/Views/SettingsView.swift#L127).

렌더링은 샘플 선택 변경에만 연결되어 있고 저장은 파일 쓰기만 수행한다. 공유 설정 상태·저장 알림·탭 복귀 시 재계산 경로가 없다. 선택을 바꾸기 전까지 이전 설정으로 만든 HTML이 남는다. 소스 상태·이벤트 흐름 검증이며 실제 Settings 저장 UI는 이번에 실행하지 않음.

수정 방향: 저장 버전이나 공유 설정 상태를 Preview 렌더링 입력으로 연결.

### 9. P2 — 호스트 Preview가 이미지 timeout 설정을 무시

위치: [PreviewWebViewRepresentable.swift:23](../../AllYouNeedQuickLook/Views/PreviewWebViewRepresentable.swift#L23).

확장은 저장한 timeout을 생성자로 넘기지만 호스트는 `PreviewWebView()`로 생성해 기본 3초를 사용한다. 파일 선택 변경에도 로더는 갱신되지 않는다. 생성자 및 값 전달 경로로 확인했으며 실제 느린 서버를 통한 시간 측정은 하지 않음.

수정 방향: 호스트에도 저장한 timeout 전달, 변경 시 로더 갱신 수명주기 정의.

### 10. P2 — 이미지 프록시가 로컬·내부망 목적지 요청 허용

위치: [ExternalImageSchemeHandler.swift:38](../../Shared/WebView/ExternalImageSchemeHandler.swift#L38).

문서 이미지가 네이티브 GET으로 이어지며 목적지 검사는 HTTP/HTTPS 스킴뿐이다. 이번에도 URLProtocol로 실제 네트워크를 대체해 `127.0.0.1`, `10.0.0.1`, `::1`의 요청 시작을 확인했다. 합성 text/plain 응답을 받은 뒤 MIME 검사에서 거절되므로 요청 자체를 방지하지 않는다.

공개 원격 이미지 지원은 의도된 기능이다. 이 항목은 내부망 목적지 통제 부재이며 실제 서비스 접속, 응답 유출, 명령 실행, 샌드박스 탈출을 입증한 것은 아니다. 피해는 접근 가능한 내부 서비스의 GET 동작에 의존한다.

수정 방향: 원격 이미지 허용 정책 결정 후 실제 연결 목적지·리다이렉트에 일관된 제한 적용. 기존 시간·크기 제한 유지.

## 검증 범위

| 검증 | 이번 결과 |
|---|---|
| XcodeGen | 현재 project.yml에서 재생성 |
| Tests scheme | 171개, 실패 0, TEST SUCCEEDED |
| 호스트 및 내장 확장 빌드 | BUILD SUCCEEDED |
| 현재 Shared 실제 WKWebView | 대조군 및 1/3/4/5/6/7번 합성 DOM 관찰 |
| 로그 성능 | 4,000~64,000개 ERROR 반복, 2번 비용 측정 |
| 이미지 주소 정책 | URLProtocol 오프라인 interception, 실제 내부망 요청 없음 |
| Settings 저장 UI / timeout 실측 | 미실행, 소스 경로 검증만 수행 |
| Finder Space / 호스트 시각 / 다크 모드 | 이번에 미실행 |
| CodeRabbit | 0.7.6 설치, 로그아웃 상태로 외부 리뷰 미실행 |

최초 XCTest는 에이전트 샌드박스의 testmanagerd 접근 제한으로 실행되지 않았다. 권한을 허용한 재실행에서 171개 통과. 제품 테스트 assertion 실패와 구분한다. 통과한 기존 테스트가 위의 재현 버그 부재를 증명하지 않는다.

제품 코드·설정·설치 앱은 변경하지 않았다. 검토용 probe 프로세스는 종료했다. 빌드가 호출한 임시 앱 등록 경로에 대해 해제를 시도했으나 lsregister는 -10814를 반환했다. 이후 `lsregister -dump`에서 `aynql-review-20260912` 경로는 발견되지 않았다. 기존 앱의 등록을 일괄 변경하지 않았다.

`.txt` Finder 라우팅은 이번에 재검증하지 않았으며 과거 관찰을 현재 결과로 계산하지 않음. 벤더 JS 내부의 전면 감사, CVE 조사, macOS 15 실기·배포 검증도 범위 밖이다.

## 재현 자료

- 기존 로컬 합성 입력: `docs/validation/artifacts/2026-09-09/ReviewProbe.swift`, `ImagePolicyProbe.swift`. 검토 시작 전에 존재한 미추적 자료로 이번 PR에는 포함하지 않음. 수정 후 회귀 입력과 assertion은 Tests 및 9월 12일 fixes 자료에 포함.
- 추가 합성 입력: [AdditionalReviewProbe.swift](artifacts/2026-09-12/AdditionalReviewProbe.swift).
- 이번 관찰 출력: [probe-results.txt](artifacts/2026-09-12/probe-results.txt), [additional-results.txt](artifacts/2026-09-12/additional-results.txt).
- 임시 빌드/테스트 로그: `/private/tmp/aynql-review-20260912-{tests,build}.log`.
- DerivedData: `/private/tmp/aynql-review-20260912`.

probe는 체크인된 XCTest 회귀 assertion이 아니라 실제 WKWebView 관찰용 도구다. 기존 9월 9일 보고서의 재현 명령에서 DerivedData·실행 파일 경로를 위 9월 12일 경로로 바꾸면 재실행 가능하다. 추가 probe도 동일한 Shared framework 링크 옵션으로 컴파일한다.
