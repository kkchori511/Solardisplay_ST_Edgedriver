# 핸드오프: Ulanzi TC001로 SmartThings 태양광 출력 표시

Claude CLI에서 이어서 작업하기 위한 정리. 아래 "확인된 것 / 미확인"을 구분해서 읽을 것.

## 목표
집 SmartThings 허브에 연결된 태양광 출력(W)을 Ulanzi TC001 픽셀 시계에 표시한다. 별도 홈서버 없이 허브 엣지 드라이버에서 시계로 직접 HTTP POST하는 방식을 목표로 한다.

## 환경 / 결정 사항
- 시계: **Ulanzi TC001** (이미 도착, 맥에서 작업 예정). TC002는 가격 때문에 제외, 앞으로 모든 기준은 TC001.
- 태양광 계측: **시하스(ShinaSystem/SiHAS) PMM-300Z2**, Zigbee 전력량계. 허브에 엣지 드라이버로 직접 연결돼 있음.
- 드라이버 설치 채널: "SiHAS Zigbee Devices" (소유자: SiHAS). 초대 링크는 로그인 필요, 채널 화면에는 이름/소유자/드라이버 목록만 보임.
- 시계 펌웨어: AWTRIX 3는 개발 종료로 알고 있어 **AWTRIX NG**(github.com/Blueforcer/awtrix-ng) 설치 예정.
- 홈서버/Home Assistant 없음 (필요 시 대안일 뿐).

## 전체 흐름
1. TC001에 AWTRIX NG 플래시 (USB-C 데이터 케이블, 맥, 크롬/엣지 웹 플래셔. Safari 불가)
2. 시계 와이파이 연결, 공유기에서 IP 고정
3. PC에서 curl로 시계 API 전송 테스트
4. 허브 드라이버 소스 수정 → 본인 채널에 배포 → PMM-300Z2 드라이버 교체

## 1단계: 플래시 전 백업 (맥 터미널)
울란지가 순정 펌웨어를 공식 배포한다는 자료는 찾지 못함. 커뮤니티 방식대로 플래시 전에 전체 백업:
```
pip install esptool
ls /dev/cu.*        # 시계 연결 후 새로 생기는 usbserial/wchusbserial 포트 확인
esptool -p /dev/cu.usbserial-xxxx -b 921600 read_flash 0x0 0x400000 tc001_factory.bin
```
복원:
```
esptool -p /dev/cu.usbserial-xxxx -b 921600 write_flash 0x0 tc001_factory.bin
```
- 충전 전용 케이블이면 인식 안 됨. 허브/어댑터 없이 직접 연결 권장.
- 포트가 안 보이면 CH340 드라이버 설치 필요할 수 있음.
- 백업 파일 `tc001_factory.bin`은 PC에 보관.

## 2~3단계: 시계 설정과 테스트
- AWTRIX NG 문서(blueforcer.github.io/awtrix-ng)에서 TC001 플래시 방법과 HTTP API 형식 확인.
- 아래는 AWTRIX 3 기준 예시이며 NG에서는 형식이 다를 수 있음 (미확인):
```
POST http://<시계IP>/api/custom?name=solar
{"text": "2.3kW", "icon": "solar", "color": "#FFD700"}
```
- TC001 화면은 32x8이라 `2.3kW`처럼 짧게 + 작은 아이콘 정도.

## 4단계: 허브 드라이버
- 공식 저장소 `SmartThingsCommunity/SmartThingsEdgeDrivers`의 `drivers/SmartThings/zigbee-power-meter`에 시하스 지원이 있음.
  - `fingerprints.yml`에 ShinaSystem PMM-300Z3가 `power-meter-consumption-report-sihas` 프로필로 등록돼 있는 것을 확인. **PMM-300Z2 항목은 직접 확인 못 함** (같은 파일에 있을 가능성).
  - `src/shinasystems/init.lua`가 시하스 전용 서브드라이버로 보임. 전력값 갱신 핸들러 끝에서 시계로 POST하면 됨.
- 내가 쓰는 드라이버가 정확히 이 소스인지는 미확인. 스마트싱스 앱 → 기기 → ⋮ → 정보 → 드라이버 이름으로 확인할 것.
- 공식 채널 드라이버는 수정 불가. 절차:
  1. 저장소 포크(또는 `zigbee-power-meter` 폴더만 복사)
  2. `src/shinasystems/init.lua` 수정
  3. 드라이버 이름/ID를 본인 것으로 변경
  4. SmartThings CLI: `edge:channels:create`, `edge:channels:enroll`, `edge:drivers:package`, 설치 후 `edge:drivers:switch`로 PMM-300Z2 드라이버 교체
- Lua 전송 예시 (IP/주소/JSON은 NG API 확인 후 수정):
```lua
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"

local function send_to_clock(watts)
  local body = string.format('{"text":"%.1fkW","color":"#FFD700"}', watts / 1000)
  http.request({
    url = "http://192.168.0.50/api/custom?name=solar",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = #body,
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.null(),
  })
end
```
- 호출이 너무 잦지 않게 최소 몇 초~1분 간격으로 제한.

## 미확인 / 확인 필요
- AWTRIX NG가 TC001을 공식 지원하는지, 웹 플래셔 사용법, `/api/custom` 요청 형식
- PMM-300Z2가 위 공식 드라이버의 fingerprints에 있는지, 실제 사용 중인 드라이버 이름
- 전력값 갱신 핸들러의 정확한 위치와 단위(W 여부)
- 엣지 드라이버에서 시계 LAN 주소로 HTTP 요청이 허브에서 막히지 않는지

## CLI에서 시킬 일 (제안)
1. 맥에서 포트 확인 후 백업과 AWTRIX NG 플래시 진행 보조
2. 포크한 저장소의 `src/shinasystems/init.lua`를 읽고 전송 코드 삽입 위치 제안/수정
3. SmartThings CLI로 채널 생성 → 패키징 → 설치 → 드라이버 교체
