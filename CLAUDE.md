# 이 레포에서 작업할 때 (Claude용)

먼저 읽기: `docs/PROJECT-STATUS.md`(드라이버 요약), 전체 가이드는 `~/projects/Solardisplay_ST_TC001/docs/PROJECT-STATUS.md`.

- 사용자는 개발/깃 초보, 모든 소통은 한국어. **push, force push, 기기 드라이버 교체는 먼저 확인받는다.**
- `main`은 안정 버전(현재 v1.1)만. 새 기능은 브랜치에서 작업, 확인 후 합치고 태그. 허브 배포 전 `git branch --show-current` 확인.
- **비밀 정보를 커밋하거나 출력하지 않는다.** 기상청 키는 TC001 레포 `.env.local`뿐. 새로 클론하면 `cp scripts/pre-commit-secrets.sh .git/hooks/pre-commit`.
- 같은 PMM-300Z2인 전기차 충전기, 전체 전기 모니터에는 이 드라이버를 적용하지 않는다.
- 허브 드라이버에서는 외부 인터넷 접속이 안 된다. 새 계산 코드는 `tests/`에 로컬 시험부터 만든다.
