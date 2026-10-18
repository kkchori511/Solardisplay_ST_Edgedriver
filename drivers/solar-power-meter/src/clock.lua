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
local TEXT_COLOR = "#FFD700"
local PUSH_INTERVAL_SECONDS = 15

local TIMER_FIELD = "solar_clock_timer"
local FAILING_FIELD = "solar_clock_failing"

local clock = {}

-- 본문 JSON을 만든다. 음수는 0으로 맞추고 정수 W로 표시한다.
function clock.build_body(watts)
  local w = math.floor(math.max(watts, 0) + 0.5)
  return string.format('{"text":"%dW","icon":"%s","textColor":"%s"}', w, ICON, TEXT_COLOR)
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
  local was_failing = device:get_field(FAILING_FIELD) == true
  if not success and not was_failing then
    -- 실패가 이어지는 동안 로그가 쌓이지 않도록 처음 한 번만 남긴다.
    log.warn(string.format("시계 전송 실패 (%s): %s", CLOCK_IP, tostring(code)))
  elseif success and was_failing then
    log.info("시계 전송 복구")
  end
  device:set_field(FAILING_FIELD, not success, {persist = false})
end

local function push_current_power(device)
  local watts = device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME)
  if type(watts) ~= "number" then return end
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
  local timer = device.thread:call_on_schedule(
    PUSH_INTERVAL_SECONDS,
    function() push_current_power(device) end,
    "solar_clock_push"
  )
  device:set_field(TIMER_FIELD, timer, {persist = false})
end

return clock
