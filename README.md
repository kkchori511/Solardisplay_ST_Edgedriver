# Solardisplay_ST_Edgedriver

**현재 버전: v1.0** — 태양광 출력(W)을 시계에 표시하는 기능까지 완성한 안정 버전.

SmartThings 엣지 드라이버 쪽 작업 레포. 시하스 PMM-300Z2 전력값이 갱신될 때 Ulanzi TC001(AWTRIX NG)로 HTTP POST를 보낸다.

- 기반 소스: [SmartThingsEdgeDrivers](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers)의 `drivers/SmartThings/zigbee-power-meter`
- 짝 레포: [Solardisplay_ST_TC001](https://github.com/kkchori511/Solardisplay_ST_TC001) (시계 펌웨어/API)

## 진행 순서
1. [x] 실제 사용 중인 드라이버 이름 확인 (SmartThings 앱 → 기기 → ⋮ → 정보)
2. [x] 공식 소스 복사 → `drivers/` 아래에 배치
3. [x] 시계 전송 코드 추가 (`src/clock.lua`, 15초 간격)
4. [x] 드라이버 이름/ID를 본인 것으로 변경
5. [ ] SmartThings CLI로 채널 생성 → 패키징 → 설치 → 드라이버 교체

자세한 내용은 [docs/handoff-tc001-solar.md](docs/handoff-tc001-solar.md) 참고.

## 구조와 결정 사항
- 쓰던 드라이버: "SiHAS Zigbee Power Meter Consumption V3(PMM-300-Z)" (시하스 채널). 소스를 구할 수 없어, 공식 `zigbee-power-meter`를 포크했다 (공식 fingerprints에 `ShinaSystem/PMM-300Z2` 있음). 문제가 생기면 앱에서 시하스 드라이버로 되돌린다.
- 위치: `drivers/solar-power-meter/` (공식 대비 변경: `config.yml`, `src/clock.lua` 추가, `src/shinasystems/init.lua`에 시작/정지 호출).
- 방식: 순간 전력 핸들러를 건드리지 않고, 15초마다 SmartThings가 계산한 `powerMeter` 값을 읽어 시계에 `PUT /api/v1/apps/pushed/solar`로 보낸다.
- 시계 IP, 아이콘, 색, 간격은 `src/clock.lua` 맨 위 상수.
- 아직 허브에서 실제 동작은 확인하지 못했다 (패키징/설치 전).

## 배포 기록 (2026-10-18)
- 채널: `Solardisplay Drivers` (`40607751-7843-4d32-98b8-a1945b4cbc33`, 비공개). 허브: 4층 SmartThings Station (`430d54dc-aa95-4727-b270-a1a42c107ea2`, `192.168.0.118`)이 등록돼 있다.
- 드라이버 ID: `471c3cca-991d-4a2d-b2d9-797c4e3dd7bb` (`packageKey: solar-power-meter-lan`). 첫 버전 `f4cd103b-fd24-4848-a924-d7273d277164`는 `lan` 권한이 없어 소켓이 `Permission Denied`로 막혔다. 이미 올린 드라이버는 권한을 바꿀 수 없어(`Permissions have been modified`) `packageKey`를 바꿔 새 드라이버로 올렸다. 첫 버전은 삭제했다 (허브 제거, 채널 해제, 드라이버 삭제).
- 교체한 기기: **태양광 발전기** (`39007be1-bf1e-40b2-9f34-9c9d318a6ce9`)만. 같은 모델(PMM-300Z2)인 "전기차 충전기"와 "전체 전기 모니터"는 기존 시하스 드라이버 그대로 둔다. 이 드라이버로 바꾸면 시계에 값이 섞인다.
- 교체 전 값: 9W, 5706.581kWh.
- 이전 드라이버(되돌릴 때): `0c975ca0-7645-4a43-89f2-4c80575cad78` (SiHAS Zigbee Power Meter Consumption V3)
  ```
  smartthings edge:drivers:switch 39007be1-bf1e-40b2-9f34-9c9d318a6ce9 --hub 430d54dc-aa95-4727-b270-a1a42c107ea2 --driver 0c975ca0-7645-4a43-89f2-4c80575cad78
  ```
- 재배포: `smartthings edge:drivers:package drivers/solar-power-meter --channel 40607751-7843-4d32-98b8-a1945b4cbc33 --hub 430d54dc-aa95-4727-b270-a1a42c107ea2`
- 첫 배포는 `init`에서만 타이머를 시작해 전송이 안 됐다. 기기 교체 시 `init`이 다시 불리지 않는 것으로 보여 `driverSwitched`, `doConfigure`에서도 시작하도록 고쳤고, 그 뒤 시계 갱신이 확인됐다.
- 허브 로그는 `smartthings edge:drivers:logcat <driverId> --hub-address 192.168.0.118` (처음 접속할 때 인증서 지문 확인 질문이 나온다).
- 시계로 보내려면 `config.yml`에 `permissions: lan: {}`가 필요하다.
- 확인: 허브 로그에 `시계 전송 성공 #1: {"text":"17W",...}` (2026-10-18 13:07).
- 시계 쪽 설정: 시간대를 `KST-9`로 변경(`PUT /api/v1/system`).

## 표시 규칙 (2026-10-18)
- 글자와 막대 색: 100W 이하 회색(흐림/일몰), 1500W 이하 노랑, 3000W 이하 주황, 3000W 초과 빨강.
- 막대: 숫자 아래 맨 아래 줄, 번개 아이콘 오른쪽 24칸. 3200W를 100%로 비례(칸당 약 133W). 3200W를 넘어도 막대는 가득 찬 채 유지되고 숫자만 실제 값으로 표시된다.
- 구간과 용량은 `src/clock.lua`의 `COLOR_STEPS`, `COLOR_MAX`, `RATED_WATTS`에서 바꾼다.
- 번개 아이콘은 GIF라 항상 노란색이다.

## 글자 배치 (2026-10-18)
- 숫자와 단위 W를 `draw` 명령으로 직접 그린다 (`text` 필드는 빈 문자열). 아이콘(8칸) 오른쪽 23칸(x=9~31)을 가운데 정렬로 쓴다.
- 숫자는 구간 색, W는 초록(`#00FF00`). W는 가운데 기둥을 위로 2칸 더 늘린 모양이다 (`UNIT_PIXELS`).
- 숫자와 W 사이는 2칸. 4자리(예: 3200W)는 22칸을 써서 1칸 남는다. 5자리는 들어가지 않는다.
- 간격, 모양, 색은 `src/clock.lua` 맨 위의 `UNIT_GAP`, `UNIT_PIXELS`, `UNIT_COLOR`에서 바꾼다.
- 시계 화면은 `GET /api/v1/display/screen`(픽셀 RGB 값)으로 읽을 수 있어, 변경 전에 화면으로 검증했다.

## 버전과 브랜치 규칙
- `main`: 안정 버전만 둔다. 지금 허브에 올라간 드라이버와 같은 코드. 현재 **v1.0** (git 태그 `v1.0`).
- 새 기능은 `main`에서 브랜치를 따서 작업한다. 예: `weather`(날씨 표시 실험).
- 브랜치에서 충분히 확인한 뒤에만 `main`에 합치고, 합칠 때 새 버전 태그(`v1.1` 등)를 붙인다.
- 허브에 배포하는 코드가 어느 브랜치/태그인지 헷갈리지 않게, 배포 전에 `git branch --show-current`로 확인한다.
- 브랜치 목록: `git branch`, 이동: `git checkout <이름>`, 새로 만들기: `git checkout -b <이름>`.

## v1.0 포함 내용
- 시하스 PMM-300Z2(태양광 발전기) 전력값을 15초마다 시계(AWTRIX NG)로 전송
- 출력 구간별 색(회색/노랑/주황/빨강)과 3200W 기준 막대, 번개 아이콘, 초록 W
- 시계 IP, 색 기준, 용량은 `src/clock.lua` 맨 위 상수
- 허브 배포: 드라이버 `471c3cca-991d-4a2d-b2d9-797c4e3dd7bb`, 버전 `2026-10-18T12:16:45` (태양광 발전기 1대에 적용)

## 비밀 정보 보호
- 인증키 같은 비밀은 레포에 넣지 않는다. `.gitignore`가 `.env*`, `*.local`, `kma_key.lua` 등을 막는다.
- 커밋 직전 검사: `cp scripts/pre-commit-secrets.sh .git/hooks/pre-commit`로 설치한다. 새로 클론하면 다시 설치해야 한다.

## V3 정보 표시 (v3-info 브랜치)
- 태양광 발전기에 전압, 전류, 주파수, 역률, 온도, 생산(역방향) 누적량을 추가했다. 자세한 내용과 기기에서 확인한 배율: [docs/v3-info-notes.md](docs/v3-info-notes.md)
- 새 프로필: `drivers/solar-power-meter/profiles/sihas-solar-v3.yml`
