-- Ulanzi TC001(AWTRIX NG) 시계로 태양광 출력(W)을 보낸다.
-- 일정 간격마다 SmartThings가 계산해 둔 powerMeter 값을 읽어 PUT한다.
-- 기본 핸들러를 건드리지 않으므로 앱에 보이는 값과 시계 값이 같다.

local capabilities = require "st.capabilities"
local cosock = require "cosock"
local log = require "log"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"

http.TIMEOUT = 3

-- 시계 설정. 시계 IP를 바꾸면 여기만 고치면 된다.
local CLOCK_IP = "192.168.0.12"
local APP_NAME = "solar"
local ICON = "bolt"
local TRACK_COLOR = "#202020"
local UNIT_COLOR = "#00FF00" -- 단위 W 색 (초록)

-- 글자는 위치를 직접 정해 그린다 (draw 명령은 아이콘을 무시하고 왼쪽 끝 x=0 기준).
-- 숫자 한 글자는 폭 3 + 간격 1 = 피치 4. 아이콘(8칸) 오른쪽 23칸(x=9~31)을 쓴다.
local AREA_LEFT = 9
local AREA_WIDTH = 23
local DIGIT_PITCH = 4
local UNIT_WIDTH = 5
local UNIT_GAP = 2 -- 숫자와 W 사이 빈 칸 (기본 폰트는 1칸)
-- W 모양: 가운데 기둥을 위로 2칸 더 늘렸다. {열, 행}, 열은 W 왼쪽 끝 기준.
local UNIT_PIXELS = {
  {0, 1}, {4, 1},
  {0, 2}, {2, 2}, {4, 2},
  {0, 3}, {2, 3}, {4, 3},
  {0, 4}, {2, 4}, {4, 4},
  {1, 5}, {3, 5},
}

-- 출력 구간별 색 (W 이하). 마지막은 그 이상 전부.
local COLOR_STEPS = {
  {max = 100, color = "#808080"},   -- 흐림/일몰: 회색
  {max = 1500, color = "#FFD700"}, -- 노랑
  {max = 3000, color = "#FFA500"}, -- 주황
}
local COLOR_MAX = "#FF0000"        -- 3000W 초과: 빨강
local RATED_WATTS = 3200           -- 막대가 가득 차는 출력. 넘어가면 100%로 고정
local PUSH_INTERVAL_SECONDS = 15

local TIMER_FIELD = "solar_clock_timer"
local COUNT_FIELD = "solar_clock_count"

local clock = {}

local function color_for(w)
  for _, step in ipairs(COLOR_STEPS) do
    if w <= step.max then return step.color end
  end
  return COLOR_MAX
end

-- 본문 JSON을 만든다. 음수는 0으로 맞추고 정수 W로 표시한다.
-- 맨 아래 줄 막대는 RATED_WATTS 대비 비율이다.
function clock.build_body(watts)
  local w = math.floor(math.max(watts, 0) + 0.5)
  local color = color_for(w)
  local percent = math.min(100, math.floor(w * 100 / RATED_WATTS + 0.5))

  local digits = tostring(w)
  local total = #digits * DIGIT_PITCH + UNIT_GAP + UNIT_WIDTH - 1
  local x0 = AREA_LEFT + math.max(0, math.floor((AREA_WIDTH - total) / 2))
  local xw = x0 + #digits * DIGIT_PITCH - 1 + UNIT_GAP

  local unit = {}
  for _, p in ipairs(UNIT_PIXELS) do
    unit[#unit + 1] = string.format("%d,%d", xw + p[1], p[2])
  end

  return string.format(
    '{"text":"","icon":"%s","draw":[["text",%d,1,"%s","%s"],["pixels","%s",%s]],'
      .. '"progress":%d,"progressColor":"%s","progressTrackColor":"%s"}',
    ICON, x0, digits, color, UNIT_COLOR, table.concat(unit, ","), percent, color, TRACK_COLOR
  )
end

local function send(device, watts)
  local body = clock.build_body(watts)
  local response = {}
  local ok, code = http.request({
    url = string.format("http://%s/api/v1/apps/pushed/%s", CLOCK_IP, APP_NAME),
    method = "PUT",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = #body,
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(response),
  })

  local success = ok ~= nil and code == 200
  local count = (device:get_field(COUNT_FIELD) or 0) + 1
  device:set_field(COUNT_FIELD, count, {persist = false})
  if not success then
    -- 15초마다 실패 이유를 남긴다 (로그 수집을 늦게 연결해도 보이도록)
    log.warn(string.format("시계 전송 실패 (%s): ok=%s code=%s", CLOCK_IP, tostring(ok), tostring(code)))
  elseif count == 1 or count % 40 == 0 then
    log.info(string.format("시계 전송 성공 #%d: %s", count, body))
  end
end

local function push_current_power(device)
  local watts = device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME)
  if type(watts) ~= "number" then
    log.warn("시계 전송 건너뜀: powerMeter 값 없음 (" .. tostring(watts) .. ")")
    return
  end
  local ok, err = pcall(send, device, watts)
  if not ok then
    log.warn("시계 전송 오류: " .. tostring(err))
  end
end

-- 드라이버가 다시 시작되어도 타이머가 겹치지 않게 기존 것을 먼저 없앤다.
function clock.stop(device)
  local timer = device:get_field(TIMER_FIELD)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
    device:set_field(TIMER_FIELD, nil, {persist = false})
  end
end

function clock.start(device)
  clock.stop(device)
  log.info(string.format("시계 전송 시작: %s (%d초 간격)", CLOCK_IP, PUSH_INTERVAL_SECONDS))
  local timer = device.thread:call_on_schedule(
    PUSH_INTERVAL_SECONDS,
    function() push_current_power(device) end,
    "solar_clock_push"
  )
  device:set_field(TIMER_FIELD, timer, {persist = false})
end

return clock
