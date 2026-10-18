# Solardisplay_ST_Edgedriver

SmartThings 엣지 드라이버 쪽 작업 레포. 시하스 PMM-300Z2 전력값이 갱신될 때 Ulanzi TC001(AWTRIX NG)로 HTTP POST를 보낸다.

- 기반 소스: [SmartThingsEdgeDrivers](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers)의 `drivers/SmartThings/zigbee-power-meter`
- 짝 레포: [Solardisplay_ST_TC001](https://github.com/kkchori511/Solardisplay_ST_TC001) (시계 펌웨어/API)

## 진행 순서
1. [ ] 실제 사용 중인 드라이버 이름 확인 (SmartThings 앱 → 기기 → ⋮ → 정보)
2. [ ] 공식 소스 복사 → `drivers/` 아래에 배치
3. [ ] `src/shinasystems/init.lua`에 시계 전송 코드 추가 (호출 간격 제한)
4. [ ] 드라이버 이름/ID를 본인 것으로 변경
5. [ ] SmartThings CLI로 채널 생성 → 패키징 → 설치 → 드라이버 교체

자세한 내용은 [docs/handoff-tc001-solar.md](docs/handoff-tc001-solar.md) 참고.
