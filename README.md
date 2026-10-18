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
