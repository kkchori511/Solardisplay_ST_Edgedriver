# V3 정보 표시 (전압, 전류, 주파수, 역률, 온도, 생산 누적량)

## 배경
태양광 발전기(PMM-300Z2)는 원래 시하스 V3 드라이버의 프로필 `sihas-energy-pmm2-plus-produced`로 표시되던 기기다.
이 드라이버(공식 포크)로 바꾸면서 공식 프로필 `power-meter-consumption-report-sihas`가 적용되어 누적 계량 정보만 남았다.
V3 프로필이 가진 정보: 전력, 누적량, 전압, 전류, 주파수, 역률, 온도, 전력량 보고, 펌웨어 업데이트, 그리고 `produced`(에너지 생산량) 컴포넌트의 누적량.

## 기기에서 확인한 값과 배율 (2026-10-18, 허브 로그에서 기기에게 직접 읽기 요청)
| 항목 | Zigbee | 배율 | 확인한 값 |
|---|---|---|---|
| 전압 | ElectricalMeasurement `RMSVoltage` 0x0505 | 나누기 10 (`ACVoltageDivisor`=10) | 0x088A -> 218.6 V |
| 전류 | `RMSCurrent` 0x0508 | 나누기 100 (`ACCurrentDivisor`=100) | 0x0008 -> 0.08 A |
| 전력 | `ActivePower` 0x050B | 곱 1, 나누기 1 | 0 W |
| 주파수 | `ACFrequency` 0x0300 | 나누기 10 (기기가 배율 속성을 지원하지 않음, V3 표시값으로 확인) | 0x0259 -> 60.1 Hz |
| 역률 | `PowerFactor` 0x0510 (Int8) | 그대로 % | 2 |
| 온도 | TemperatureMeasurement `MeasuredValue` 0x0000 | 나누기 100 | 2423 -> 24.2 C |
| 소비 누적 | SimpleMetering `CurrentSummationDelivered` 0x0000 | 나누기 1000 | 5706.713 kWh |
| 생산 누적 | SimpleMetering **0x0001** (CurrentSummationReceived) | 나누기 1000 | 0 kWh |

- 생산 누적(0x0001)은 이 라이브러리에 이름이 없어 번호로 읽고 받는다 (`cluster_base.read_attribute`). 기기는 지원한다 (`0x0002`, `0x0003`은 미지원).
- 기기는 전압, 역률, 온도, 주파수를 스스로 보고한다. 전류와 생산량은 보고가 없어도 2분마다 읽어서 갱신한다.

## 구현
- 프로필 `profiles/sihas-solar-v3.yml`: V3와 같은 기능 구성(`afterguide46998.frequencyMeasurement`, `afterguide46998.powerfactorMeasurement` 커스텀 기능 포함, `produced` 컴포넌트). 업로드가 허용되는 것을 확인했다.
- `fingerprints.yml`: PMM-300Z2만 새 프로필로 연결 (Z1, Z3는 기존 그대로).
- `src/shinasystems/v3_info.lua`: 값 처리, 배율, 2분 주기 읽기, 이미 등록된 기기를 한 번 새 프로필로 바꾸기(`try_update_metadata`).
- 안전장치: 프로필에 기능이 없거나 `produced` 컴포넌트가 없으면 이벤트를 내지 않는다.
- 로컬 시험(가짜 기기)과 허브 배포 후 기기 상태로 확인했다. 전압 218.2 V, 전류 0.08 A, 주파수 60.1 Hz, 역률 2 %, 온도 24.2 C.

## 구현하지 않은 것 (V3 프로필에는 있었음)
- 설정 3개: 누적(소비) 리셋, 누적(생산) 리셋, **CT 설치 방향**(자동/수동 정방향/수동 역방향). 기기에 쓰는 속성 번호를 알지 못해 넣지 않았다.
- CT 방향이 "자동"이면 기기는 값을 모두 양수로 취급해 생산 누적량이 0으로 남는다 (Zigbee2MQTT 문서). 태양광은 "수동"이어야 생산 누적량이 나온다. 현재 기기에 저장된 방향은 확인하지 못했다.
