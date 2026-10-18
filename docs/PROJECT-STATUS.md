# 드라이버 쪽 현황 요약

작성: 2026-10-18 (v1.1 기준). **프로젝트 전체 현황과 이어가기 가이드는 TC001 레포의 `docs/PROJECT-STATUS.md`** (`~/projects/Solardisplay_ST_TC001/docs/PROJECT-STATUS.md`). 이 문서는 드라이버 중심 요약이다.

## 무엇인가
시하스 PMM-300Z2(태양광 발전기)용 SmartThings 엣지 드라이버. 공식 `zigbee-power-meter`를 포크했다.
- 태양광 출력(W)을 15초마다 TC001 시계(`192.168.0.12`)로 보낸다 (`src/clock.lua`).
- 시하스 V3 드라이버가 보여주던 정보(전압, 전류, 주파수, 역률, 온도)를 표시한다 (`src/shinasystems/v3_info.lua`).
- **월 누적 전력량**: 소비 누적량 - 이번 달 시작값, 달(한국 시간)이 바뀌면 0부터 다시 측정 (`monthly` 컴포넌트).

## 구조
```
drivers/solar-power-meter/
  config.yml                  이름 'Solar Power Meter TC001', packageKey solar-power-meter-lan, permissions: zigbee + lan
  fingerprints.yml            PMM-300Z2 -> sihas-solar-monthly-v2 (Z1, Z3는 공식 프로필 그대로)
  profiles/sihas-solar-monthly-v2.yml   main + monthly 컴포넌트 (커스텀 기능 afterguide46998.* 포함)
  src/clock.lua               시계로 PUT (태양광 화면 본문 생성: 구간별 색, 막대, W 글자 위치)
  src/shinasystems/init.lua   시하스 서브드라이버 (공식 코드 + 시작/정지, 누적 처리 뒤 월 누적 호출)
  src/shinasystems/v3_info.lua  V3 정보 처리, 월 누적, 프로필 이동
  (나머지는 공식 코드: bituo, ezex, frient, configurations.lua 등. 공식 시험 src/test는 실행 불가)
tests/                        로컬 Lua 시험 (허브 없이). tests/README.md 참고
scripts/pre-commit-secrets.sh 커밋 직전 비밀 검사 (cp scripts/pre-commit-secrets.sh .git/hooks/pre-commit)
docs/v3-info-notes.md         기기에서 확인한 배율, 월 누적 설계, 프로필 이름표 주의
```

## 배포 정보
- 채널 `Solardisplay Drivers` `40607751-7843-4d32-98b8-a1945b4cbc33`, 허브 `430d54dc-aa95-4727-b270-a1a42c107ea2`(`192.168.0.118`), 드라이버 `471c3cca-991d-4a2d-b2d9-797c4e3dd7bb`, 배포 버전 `2026-10-18T13:22:20`.
- 적용 기기는 태양광 발전기 1대(`39007be1-bf1e-40b2-9f34-9c9d318a6ce9`). 같은 모델의 전기차 충전기, 전체 전기 모니터는 기존 시하스 V3 드라이버(`0c975ca0-7645-4a43-89f2-4c80575cad78`)를 그대로 쓴다. **이 드라이버로 바꾸면 시계에 값이 섞인다**(`clock.lua`는 모델이 PMM-300Z2인 모든 기기에서 도는 구조).
- 배포: `smartthings edge:drivers:package drivers/solar-power-meter --channel <채널> --hub <허브>` (배포 전 `git branch --show-current` 확인).
- 로그: `smartthings edge:drivers:logcat <드라이버ID> --hub-address 192.168.0.118` (처음 접속 시 인증서 확인은 사람이 y).

## 알아둘 제약 (자세한 건 TC001 문서 5번)
- 허브 드라이버는 외부 인터넷 주소를 못 찾는다 → 날씨는 시계 스크립트가 받는다.
- 이미 올린 packageKey는 권한을 못 바꾼다. 같은 프로필 이름은 기존 기기에 반영되지 않는다(새 이름 + 코드가 기기를 한 번 옮김).
- 월 누적 값은 저장 필드(`monthly_key`, `monthly_base`, `monthly_last`)에 있다. 드라이버가 재시작돼도 이어서 센다. 11월 1일에 처음 실제 월 전환을 확인한다.

## 남은 일
- 11월 1일 월 전환 확인, 월 누적 전력량을 시계에 표시할지 결정, 다른 전력량계 지원, V3의 CT 방향/리셋 설정(기기 속성 번호 미확인). 자세한 목록은 TC001 문서 7번.
