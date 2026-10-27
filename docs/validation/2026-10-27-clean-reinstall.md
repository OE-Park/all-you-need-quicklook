# 중복 표시 조사와 클린 재설치

2026-10-27 KST. 소스 기준 커밋 `7e6a9f3`, 브랜치 `feat/quicklook-runtime-file-type-settings`.
현재 상태 기준은 [PROJECT_STATUS.md](../../PROJECT_STATUS.md).

## 조사와 실제 삭제

사용자 스크린샷의 AllYouNeedQuickLook 두 행을 시스템 설정에서 재현했다.
현재 BTM/Launch Services에는 정식 앱과 내장 확장이 각각 1개로 조회됐다.
시스템 설정을 완전히 종료하고 다시 열자 앱 행이 1개로 갱신됐다.
이는 오래된 화면 상태가 남았다는 근거이며, 단순히 앱 사본 2개가 설치됐다고 추정하지 않았다.

요청대로 재설치 전 별도 제거 단계도 수행했다.

- 현재 앱과 프로젝트 식별자로 확인한 빌드 사본·내장/독립 확장 등록 해제.
- 기존 `/Applications/AllYouNeedQuickLook.app`, 재설치 staging 앱과 standalone appex 제거.
- 기존 설정·컨테이너 경로 10개 초기화, 호스트 TCC reset, Quick Look 캐시 초기화.
- Application Support의 기존 config.json 부재 확인.
- pluginkit 프로젝트 확장 no matches 확인.
- 시스템 설정을 다시 실행하고 확장 목록 로딩 완료 후 프로젝트 행 **0개** 확인.

이 작업은 프로젝트 앱 네임스페이스만 대상으로 했다. 시스템 전체 Launch Services/BTM DB를
리셋하거나 다른 앱의 백그라운드 설정을 변경하지 않았다.

## 새 설치와 확인

- 클린 Release 빌드 BUILD SUCCEEDED. `build/clean-reinstall-20261027/build.log`.
- 올바른 signature identifier와 bound Info.plist 확인 후 보관한 설치 아카이브로 재설치.
- 설치 위치 `/Applications/AllYouNeedQuickLook.app` (랜덤 접미사 없음).
- 첫 실행 전 config.json 없음, 첫 실행 UI는 SF Mono 13 / log·txt 기본값 확인.
- 시스템 설정 전체 목록에서 앱 행 **1개**, 상세 화면에서 확장 1개 및 on 확인.
- Finder Space에서 sample.ps1 강조와 HTML resource 경로 `/Applications/AllYouNeedQuickLook.app/Contents/Frameworks/Shared.framework/Resources/` 확인.
- 설치용 zip 및 별도 DerivedData 제거. 최종 조사에서 프로젝트 앱 사본 1개와 활성 확장 1개 확인.

시스템 설정을 새로 실행한 **0개 → 1개** 확인을 이번 완료 기준으로 삼았다.
수정한 제품 코드는 없으므로 XCTest를 반복 실행하지 않았다. 직전 제품 테스트 285개 통과와
이번 새 Release 빌드·설치·UI 검증을 구분한다.

## 잔존 범위와 원본

macOS가 보호하는 컨테이너 메타데이터 9개와 디렉터리 껍데기는 삭제 시 Operation not permitted.
각 오류는 파일/부모 디렉터리로 총 18건이며, 제거 직후 해당 경로의 실제 데이터 파일은 0개였다.
새 앱 실행으로 정상 기본 런타임 데이터는 다시 생성된다. OS 관리 메타데이터까지 제거했다고
주장하지 않으며 보호 설정을 우회하지 않았다.

조사 범위는 Applications, 사용자 Applications, Projects, DevTools, Xcode DerivedData,
임시 폴더, Downloads, Desktop, Codex worktrees, Users/Shared와 Spotlight/pluginkit다.
접근 불가 경로 58개가 있으므로 접근 불가 영역까지 사본 부재를 단정하지 않는다.

로컬 감사 자료는 Git 제외 경로 `build/clean-reinstall-20261027/`에 있다.
`inventory-before.json`, `uninstall-result.json`, `inventory-after.json`,
`zero-app-settings.json`, `one-app-settings.json` 및 삭제 전후 화면·기본 설정·Finder 화면을 저장했다.
전체 BTM/LS 덤프와 시스템 설정 화면에는 다른 앱 정보가 포함되므로 공개 저장소에는 넣지 않는다.

빌드 플래그 `REGISTER_APP_WITH_LAUNCH_SERVICES=NO`만으로 자동 등록이 억제되지 않는 것도
로그에서 확인했다. 따라서 실제 staging 경로 등록을 명시적으로 해제하고 앱 사본을 제거했다.
향후 빌드 등록 예방책이 이 플래그 하나로 해결됐다고 기록하지 않는다.
