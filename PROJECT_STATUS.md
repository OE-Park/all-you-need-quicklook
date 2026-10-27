# All You Need QuickLook 진행상황

문서 갱신일: 2026-10-27 KST

현재 작업은 **소스코드·스크립트 확장 지원 확대 및 네이티브 활성화 방식 정리**다.
소스 타입 61개 그룹에 확장자 252개 선언, 시스템·편집기 타입 48개 구체 지원 선언을 추가했다.
PowerShell 등 공식 추가 문법 30개, BOM 기반 Unicode 디코더, 서식 전용 UI 안내를 반영했다.
정식 `/Applications/AllYouNeedQuickLook.app`을 교체하고 Finder에서 PowerShell·UTF-16 한글·배치·Bash·sh·CMake·일반 텍스트 대체 표시를 확인했다.
활성화는 macOS 시스템 설정에서 관리하며 기존 사용자 설정은 보존했다.

최신 근거: [소스 확장 검증](docs/validation/2026-10-27-source-formats.md).
지원 목록: [SOURCE_FORMATS.md](docs/SOURCE_FORMATS.md).
아래 이전 PR 검증·정리 기록은 이 문단의 최신 상태보다 우선하지 않는다.

## 작업 폴더와 Git

| 항목 | 위치 또는 상태 |
| --- | --- |
| **작업 기준 폴더** | `/Users/yohanpark/Projects/DevFolder/Workspace/yohanpark-dev/public_repos/all-you-need-quicklook` |
| 브랜치 | `feat/quicklook-runtime-file-type-settings` |
| 제출 커밋 | [`eae3fa6c1655e7c4bbd7949aea1df3528baf578f`](https://github.com/OE-Park/all-you-need-quicklook/commit/eae3fa6c1655e7c4bbd7949aea1df3528baf578f) |
| PR | [#14 Improve Finder preview settings, image rendering, and isolated testing](https://github.com/OE-Park/all-you-need-quicklook/pull/14) — OPEN, 미머지 |
| 대상 브랜치 | `main` — 제출 시 기준 `8cafa6d81e28636e39d297c0174b7b5edeeb2966` |
| PR 충돌 | 조회 시 MERGEABLE, 충돌 없음. 병합 상태 BLOCKED는 진행 중 검사·저장소 조건과 별개 확인 필요 |
| 리뷰 수정 | 기존 PR 브랜치에 후속 커밋으로 반영. 정확한 HEAD는 `git rev-parse HEAD`로 확인 |

**별도 사본과 혼동하지 않는다.**
`/Users/yohanpark/Projects/DevTools/System-Tools/all-you-need-quicklook`은 같은 origin을
쓰는 다른 체크아웃이다. 그곳의 브랜치·HEAD·미커밋 상태를 이 작업의 상태로 사용하지 않는다.
이번 작업은 그 저장소의 고정 커밋 `7c75faf`에서 런타임 코드를 재사용한 뒤,
위 DevFolder에서 검증하고 최신 `origin/main` 위로 정리했다.

## 구현 상태

| 영역 | 현재 반영 내용 | 주요 위치 |
| --- | --- | --- |
| 호스트 앱 | Welcome·Settings·Preview 연결, 샘플 미리보기 | `AllYouNeedQuickLook/App.swift`, `AllYouNeedQuickLook/Views/` |
| Quick Look 진입 | 파일 읽기·렌더러 선택·설정 적용·웹뷰 표시 | `QuickLookExtension/PreviewViewController.swift` |
| 확장자 설정 | 점·대소문자·공백 정규화, Add 즉시 저장, 중복 추가 시 기존 값 보존 | `Shared/Config/FileTypeSupport.swift`, `AllYouNeedQuickLook/Views/SettingsView.swift` |
| Finder 지원 안내 | bundled 타입 선언으로 지원·미지원·알 수 없는 타입 구분 | `Shared/Config/FileTypeSupport.swift`, `project.yml` |
| 시스템 설정 | 일반 → 로그인 항목 및 확장 프로그램으로 연결, 훑어보기 활성화 안내 | `AllYouNeedQuickLook/Support/ExtensionSettings.swift` |
| 설정 공유 | App Group에서 Application Support로 이동, 손상 설정의 기본값·경고 표시 | `Shared/Config/ConfigLoader.swift`, `project.yml` |
| 렌더링 | Markdown·텍스트/로그·소스·JSON/YAML/TOML·Notebook | `Shared/Renderers/`, `Shared/Config/SyntaxLanguageMap.swift` |
| 이미지·차트 | 검증된 상대경로 이미지·SVG, Notebook Plotly JSON/typed-array 출력 | `Shared/WebView/LocalImageSchemeHandler.swift`, `Shared/Renderers/NotebookRenderer.swift` |
| 보안 경계 | 문서별 nonce, 인라인 번들 JS/CSS, CSP·탐색 제한 | `Shared/WebView/PreviewWebView.swift`, `Shared/Renderers/HTMLTemplate.swift` |
| 테스트 빌드 | 랜덤 앱 이름·bundle ID·설정 경로 격리, Finder 테스트 식별 표시 | `script/`, `Shared/Renderers/PreviewBuildIdentity.swift` |
| 앱 아이콘 | 브랜드 원본과 macOS Asset Catalog | `assets/brand/`, `AllYouNeedQuickLook/Assets.xcassets/` |

확장자 설정은 **표시 설정**이다. Finder 호출 대상은 앱의 `QLSupportedContentTypes`
선언에 따른다. 시스템 설정에서 훑어보기를 켜도 새 파일 형식이 등록되거나 특정 제공자가
항상 선택되는 것은 아니다. 실제로 기존 `/Applications` 제공자가 선택되는 경우를 확인했다.

## 검증 결과

### 로컬 실행

- 리뷰 수정 후 **XCTest 285개 통과, 실패 0개**.
- 랜덤 앱 `dd38b75d`의 호스트·확장 빌드 및 deep/strict 서명 검증 통과. 이 사본은 실행하지 않음.
- 컴퓨터 도구로 확장자 즉시 저장, 미지원 안내, 호스트 YAML·Notebook, 시스템 설정 연결 확인.
- Finder Space에서 빌드 식별 표시를 기준으로 YAML·Markdown·Notebook·로그·Plotly·로컬 이미지 확인.
- 최종 실행 사본 `2f543413`에서 JSON 구문 강조와 손상 설정 경고·기본값 표시 확인.
- Markdown·로컬 이미지의 라이트/다크 대표 사례 확인. 시스템 화면 모드는 원래 Light로 복원.
- 임시 손상시킨 테스트 설정은 원본 바이트로 복원. 기존 설치 확장의 활성 상태도 복원.

시각 확인·Finder 제공자 귀속·실행 명령·스크린샷별 근거는
[검증 보고서](docs/validation/2026-10-26-runtime-and-file-types.md)에 있다.
단위 테스트·live WKWebView 통과를 모든 Finder 동작의 성공으로 확대하지 않는다.

### 최초 제출 GitHub 검사 스냅샷

아래는 최초 제출 커밋 `eae3fa6`에 대해 19:52 KST 재확인한 결과다. 후속 수정의 CI 통과를 뜻하지 않는다. 최신 결과는 PR에서 확인한다.

| 검사 | 조회 결과 |
| --- | --- |
| [CI Test and build](https://github.com/OE-Park/all-you-need-quicklook/actions/runs/40302588343/job/121503815195) | SUCCESS |
| [Dependency review](https://github.com/OE-Park/all-you-need-quicklook/actions/runs/40302588362/job/121503815122) | SUCCESS |
| [CodeQL Analyze actions](https://github.com/OE-Park/all-you-need-quicklook/actions/runs/40302588323/job/121503815006) | SUCCESS |
| [CodeQL Analyze swift](https://github.com/OE-Park/all-you-need-quicklook/actions/runs/40302588323/job/121503815422) | SUCCESS |
| 별도 CodeQL 항목 | SUCCESS |

## 샘플과 빌드 산출물 위치

프로젝트 안의 아래 경로는 저장소 루트 기준이다. `build/`는 Git 제외 대상이며
다른 머신에는 전달되지 않는다.

| 용도 | 위치 |
| --- | --- |
| 데스크탑 원본 샘플 | `/Users/yohanpark/Desktop/AYNQL-test` |
| 공용 샘플 사본 | `/Users/yohanpark/Projects/TEST_SAMPLES/all-you-need-quicklook/2026-10-26` — 81개 원본 파일의 복사 해시 확인 |
| 최종 확인용 사본 | `/Users/yohanpark/Projects/TEST_SAMPLES/all-you-need-quicklook/final-checks` |
| 임시 네트워크 재현 문서 | `/Users/yohanpark/Projects/TEST_SAMPLES/all-you-need-quicklook/session-network-probe` — loopback 서버는 종료됨 |
| 원본 코드 백업 | `build/before-runtime-integration-20261026/` — 최초 미추적 Notebook 파일 포함 |
| 최근 빌드 경로 색인 | `build/test-runs/latest.json` |
| 현재 설치·Finder 검증 앱 | `/Applications/AllYouNeedQuickLook.app` — 랜덤 접미사 없음 |
| 이전 테스트 앱 | `2f543413`, `dd38b75d` 및 validation Debug 앱 삭제. latest.json은 과거 기록 |
| 이전 테스트 설정 | 삭제·초기화. macOS 보호 컨테이너 메타데이터 일부만 잔존 |
| 일반 앱 설정 | `~/Library/Application Support/AllYouNeedQuickLook/config.json` |
| 새 검증용 샘플 | `/Users/yohanpark/Projects/TEST_SAMPLES/all-you-need-quicklook/review-clean-install` |
| 테스트 로그 | `build/runtime-tests-final.log`, `build/pr-rebased-tests.log`, `build/pr-rebased-build.log` |
| 보존한 UI 증거 | `docs/validation/artifacts/2026-10-26/` 및 `2026-10-26-review/` |
| 리뷰 테스트·설치 로그 | `build/pr-review-green.log`, `build/clean-install/release-build.log`, `build/clean-install/final-inventory.json` |

리뷰 후 정리에서 기존 앱 4개와 독립 테스트 확장 사본을 제거했다. 재조사에서
확인된 프로젝트 앱은 정식 설치본 1개, 등록된 확장은 그 안의 활성 확장 1개다.
탐색 중 접근 불가 경로 58개가 있어 머신의 접근 불가 영역까지 부재를 증명하지 않는다.
기존 설정 16개 경로를 정리했으며 OS 보호 메타데이터와 새 실행으로 생성된 기본 데이터는 남는다.

## 다음 작업과 미해결 항목

1. **후속 커밋의 PR 검사·외부 재리뷰 확인.** 리뷰 스레드는 자동으로 해결 처리하지 않음.
2. **외부 이미지 전송 재설계.** 응답 25 MiB 제한을 실제로 적용한 뒤 재활성화 검토.
   현재는 CSP와 이미지 스크립트가 HTTP(S)를 차단하며 로컬·임베디드 이미지만 지원.
3. **81개 corpus의 양쪽 화면 모드 전수검사.** 지금 결과는 대표 사례의 실제 확인.
4. **Plotly 최초 미리보기 시간 측정과 제3자 의존성 라이선스 전수 감사.**
   Plotly 공식 MIT 원문·배포 출처는 검증했지만 의존성 전수 감사는 아님.
5. **배포 검증.** 정식 코드 서명·notarization·배포 산출물 검증. 현재 설치는 로컬 ad-hoc 빌드.

PR은 열려 있지만 릴리스 검증 완료 상태는 아니다. 기존 App Group 설정은 자동 복구하지 않고
명시적 JSON 가져오기로만 옮긴다. 이번 설치 후에는 가져오기 테스트를 마친 뒤 기본값으로 복원했다.

## 작업 재개

1. 이 문서에서 작업 기준 경로·브랜치·남은 항목 확인.
2. `git status --short`, `git branch --show-current`, `git rev-parse HEAD`로 실제 상태 재확인.
3. 구현 변경은 `project.yml`에서 관리하고 `xcodegen generate`로 프로젝트 재생성.
4. `./script/build_and_run.sh --build-only`로 기존 테스트 사본을 점검하고 새 격리 앱 빌드.
5. `build/test-runs/latest.json`의 정확한 사본으로 검증하고, Finder에서는 테스트 빌드 표시 확인.
6. 결과는 검증 보고서에 실행·대기를 나눠 기록하고 Projects 데일리 기록 연결.

- [보충 구현 계획](docs/superpowers/plans/2026-10-26-runtime-and-file-type-settings.md)
- [현재 인계와 과거 기록](docs/superpowers/HANDOFF.md)
- [검증 보고서와 증거](docs/validation/2026-10-26-runtime-and-file-types.md)
