# Solardisplay_ST_Edgedriver

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
- 드라이버 ID: `471c3cca-991d-4a2d-b2d9-797c4e3dd7bb` (`packageKey: solar-power-meter-lan`). 첫 버전 `f4cd103b-fd24-4848-a924-d7273d277164`는 `lan` 권한이 없어 소켓이 `Permission Denied`로 막혔다. 이미 올린 드라이버는 권한을 바꿀 수 없어(`Permissions have been modified`) `packageKey`를 바꿔 새 드라이버로 올렸다. 첫 버전은 허브/채널에 남아 있다.
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
