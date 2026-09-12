# 검증 기록

작업 보고서는 이 폴더에 날짜별 Markdown으로 보존한다. 재현 자료는
`artifacts/<날짜>/`에 두고 보고서에서 상대 링크한다. 임시 빌드 경로는 실행 환경의
식별자로만 기록하고 보고서·증거의 유일한 보관 위치로 사용하지 않는다.

아티팩트 로그는 커밋 전에 `scripts/sanitize-validation-log.sh`로 정리한다.
계정 경로(`/Users/<user>`), 소유자 환경변수, `export PATH`, xcodebuild destination의
하드웨어 id를 자리표시자로 바꾼다. 제품 번들 식별자와 테스트·빌드 결과는 그대로 둔다.
치환은 멱등이므로 재실행해도 안전하고, 실행 후 남은 식별자를 grep으로 확인한다.

보고서는 대상 커밋/변경, 원인, 수정, 실행 명령, assertion, 시각 확인,
실제 앱/Finder 통합 확인과 남은 검증을 구분한다. 재사용 가능한 문제 해결 지식은
Obsidian `Knowledge/07_DevArchive/`에 기록하고 해당 보고서를 연결한다.

- [2026-09-07 다크 모드와 호스트 Preview 복구](2026-09-07-dark-mode.md)
- [2026-09-07 작업 종료·AI 인계](2026-09-07-handoff.md)
- [2026-09-12 검증된 버그 수정과 Finder 통합 검증](2026-09-12-bug-fixes.md)
