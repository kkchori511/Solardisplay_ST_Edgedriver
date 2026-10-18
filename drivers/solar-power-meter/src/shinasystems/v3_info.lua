-- 시하스 V3 드라이버가 보여주던 정보를 표시한다: 전압, 전류, 주파수, 역률, 온도.
-- 그리고 월 누적 전력량: 소비 누적량(CurrentSummationDelivered, 이 기기에서는 태양광 총 발전량)에서
-- 이번 달 시작 시점의 값을 뺀 값. 달(한국 시간)이 바뀌면 시작값을 새로 잡아 0부터 다시 센다.
-- 배율은 기기에게 직접 물어 확인한 값이다 (2026-10-18 허브 로그):
--   전압 /10 (ACVoltageDivisor=10), 전류 /100 (ACCurrentDivisor=100), 전력 /1,
--   주파수 0x0259=601 -> 60.1Hz (/10, 기기는 배율 속성을 지원하지 않음),
--   온도 /100 (2423 -> 24.23C), 누적량 /1000 (SimpleMetering Divisor=1000), 역률은 % 그대로.

local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local log = require "log"

local EM = clusters.ElectricalMeasurement
local SM = clusters.SimpleMetering
local TM = clusters.TemperatureMeasurement

local v3 = {}

v3.PROFILE = "sihas-solar-monthly-v2"

local FREQUENCY_CAPABILITY = "afterguide46998.frequencyMeasurement"
local POWER_FACTOR_CAPABILITY = "afterguide46998.powerfactorMeasurement"

local POLL_SECONDS = 120
local TIMER_FIELD = "v3_info_timer"
-- 프로필 이름마다 한 번씩만 기기를 옮긴다 (프로필 이름을 바꾸면 자동으로 다시 옮겨진다)
local PROFILE_FIELD = "profile_requested:" .. v3.PROFILE
local MONTHLY_COMPONENT = "monthly"
local MONTHLY_SAVE_SECONDS = 1800 -- 마지막 누적값은 30분마다만 저장한다

local EM_FIELDS = {
  voltage_mult = "em_voltage_mult",
  voltage_div = "em_voltage_div",
  current_mult = "em_current_mult",
  current_div = "em_current_div",
}

local function supports(device, capability_id)
  return device:supports_capability_by_id(capability_id)
end

local function round1(x)
  return math.floor(x * 10 + 0.5) / 10
end

-- ---------- 값 처리 (Zigbee 보고/읽기 응답 공통) ----------

function v3.voltage_handler(driver, device, value, zb_rx)
  if not supports(device, "voltageMeasurement") then return end
  local mult = device:get_field(EM_FIELDS.voltage_mult) or 1
  local div = device:get_field(EM_FIELDS.voltage_div) or 10
  device:emit_event(capabilities.voltageMeasurement.voltage({value = round1(value.value * mult / div), unit = "V"}))
end

function v3.current_handler(driver, device, value, zb_rx)
  if not supports(device, "currentMeasurement") then return end
  local mult = device:get_field(EM_FIELDS.current_mult) or 1
  local div = device:get_field(EM_FIELDS.current_div) or 100
  device:emit_event(capabilities.currentMeasurement.current({value = value.value * mult / div, unit = "A"}))
end

function v3.frequency_handler(driver, device, value, zb_rx)
  local capability = capabilities[FREQUENCY_CAPABILITY]
  if capability == nil or not supports(device, FREQUENCY_CAPABILITY) then return end
  device:emit_event(capability.frequency({value = round1(value.value / 10), unit = "Hz"}))
end

function v3.power_factor_handler(driver, device, value, zb_rx)
  local capability = capabilities[POWER_FACTOR_CAPABILITY]
  if capability == nil or not supports(device, POWER_FACTOR_CAPABILITY) then return end
  device:emit_event(capability.powerFactor({value = value.value, unit = "%"}))
end

function v3.temperature_handler(driver, device, value, zb_rx)
  if not supports(device, "temperatureMeasurement") then return end
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = round1(value.value / 100), unit = "C"}))
end

-- ---------- 월 누적 전력량 ----------

local KST_OFFSET = 9 * 3600

-- 한국 시간 기준 연월 (예: 202610)
function v3.month_key(t)
  local d = os.date("!*t", (t or os.time()) + KST_OFFSET)
  return d.year * 100 + d.month
end

-- 순수 계산. state = {key=, base=, last=}: 저장된 월, 월 시작값, 직전 누적값.
-- 돌려주는 것: 새 state, 월 누적(kWh)
--  - 처음이거나 기준값이 없으면 지금 값을 시작값으로 한다 (그때부터 센다)
--  - 달이 바뀌면 직전에 본 누적값(밤에는 발전이 없어 자정 값과 같다)을 새 시작값으로 한다
--  - 누적값이 시작값보다 작아지면(기기 초기화) 지금 값을 새 시작값으로 한다
function v3.monthly_next(state, key, total)
  local base
  if state.key == nil or state.base == nil then
    base = total
  elseif state.key ~= key then
    if state.last ~= nil and state.last <= total then base = state.last else base = total end
  else
    base = state.base
    if total < base then base = total end
  end
  return {key = key, base = base, last = total}, total - base
end

local function round3(x)
  return math.floor(x * 1000 + 0.5) / 1000
end

local function emit_monthly(device, monthly)
  local components = device.profile and device.profile.components
  local component = components and components[MONTHLY_COMPONENT]
  if component == nil then return end
  device:emit_component_event(component, capabilities.energyMeter.energy({value = round3(monthly), unit = "kWh"}))
end

-- 소비 누적량(kWh)이 보고될 때마다 부른다
function v3.update_monthly(device, total, now)
  now = now or os.time()
  local state = {
    key = device:get_field("monthly_key"),
    base = device:get_field("monthly_base"),
    last = device:get_field("monthly_last_mem") or device:get_field("monthly_last"),
  }
  local new_state, monthly = v3.monthly_next(state, v3.month_key(now), total)

  if new_state.key ~= state.key or new_state.base ~= state.base then
    device:set_field("monthly_key", new_state.key, {persist = true})
    device:set_field("monthly_base", new_state.base, {persist = true})
    log.info(string.format("월 누적 시작값: %d년 %d월, 기준 %.3f kWh", new_state.key // 100, new_state.key % 100, new_state.base))
  end

  device:set_field("monthly_last_mem", total, {persist = false})
  if now - (device:get_field("monthly_saved_at") or 0) >= MONTHLY_SAVE_SECONDS then
    device:set_field("monthly_last", total, {persist = true})
    device:set_field("monthly_saved_at", now, {persist = false})
  end

  emit_monthly(device, monthly)
end

-- 시작할 때 저장된 값으로 월 누적을 바로 보여준다 (다음 보고를 기다리지 않도록)
function v3.show_stored_monthly(device)
  local base = device:get_field("monthly_base")
  local last = device:get_field("monthly_last_mem") or device:get_field("monthly_last")
  if base ~= nil and last ~= nil and device:get_field("monthly_key") == v3.month_key() then
    emit_monthly(device, math.max(0, last - base))
  end
end

-- 기기가 알려주는 배율을 저장한다
local function store_field(field)
  return function(driver, device, value, zb_rx)
    device:set_field(field, value.value, {persist = true})
  end
end

-- Zigbee 속성 핸들러 표 (shinasystems/init.lua의 zigbee_handlers.attr에 합친다)
function v3.attr_handlers()
  return {
    [EM.ID] = {
      [EM.attributes.RMSVoltage.ID] = v3.voltage_handler,
      [EM.attributes.RMSCurrent.ID] = v3.current_handler,
      [EM.attributes.ACFrequency.ID] = v3.frequency_handler,
      [EM.attributes.PowerFactor.ID] = v3.power_factor_handler,
      [EM.attributes.ACVoltageMultiplier.ID] = store_field(EM_FIELDS.voltage_mult),
      [EM.attributes.ACVoltageDivisor.ID] = store_field(EM_FIELDS.voltage_div),
      [EM.attributes.ACCurrentMultiplier.ID] = store_field(EM_FIELDS.current_mult),
      [EM.attributes.ACCurrentDivisor.ID] = store_field(EM_FIELDS.current_div),
    },
    [SM.ID] = {},
    [TM.ID] = {
      [TM.attributes.MeasuredValue.ID] = v3.temperature_handler,
    },
  }
end

-- ---------- 읽기 요청과 주기 확인 ----------

local function read(device, cluster, attribute)
  local ok, err = pcall(function() device:send(cluster.attributes[attribute]:read(device)) end)
  if not ok then log.warn("v3: 읽기 실패 " .. attribute .. " " .. tostring(err)) end
end

function v3.read_all(device, with_scales)
  if with_scales then
    for _, name in ipairs({"ACVoltageMultiplier", "ACVoltageDivisor", "ACCurrentMultiplier", "ACCurrentDivisor"}) do
      read(device, EM, name)
    end
  end
  for _, name in ipairs({"RMSVoltage", "RMSCurrent", "ACFrequency", "PowerFactor"}) do
    read(device, EM, name)
  end
  read(device, TM, "MeasuredValue")
  -- 누적량도 함께 읽어 월 누적이 바로 계산되게 한다 (보고를 기다리지 않도록)
  read(device, SM, "CurrentSummationDelivered")
end

function v3.stop(device)
  local timer = device:get_field(TIMER_FIELD)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
    device:set_field(TIMER_FIELD, nil, {persist = false})
  end
end

-- 시작: 프로필 적용, 배율 읽기, 2분마다 값 확인 (기기가 보고하지 않는 값도 갱신되도록)
function v3.start(device)
  v3.stop(device)
  if device:get_model() ~= "PMM-300Z2" then return end

  -- 이미 다른 프로필로 등록된 기기를 한 번 V3 프로필로 바꾼다
  if not device:get_field(PROFILE_FIELD) then
    device:set_field(PROFILE_FIELD, true, {persist = true})
    local ok, err = pcall(function() device:try_update_metadata({profile = v3.PROFILE}) end)
    log.info("v3: 프로필 적용 요청 " .. v3.PROFILE .. " ok=" .. tostring(ok) .. " " .. (ok and "" or tostring(err)))
  end

  device.thread:call_with_delay(10, function() v3.read_all(device, true) end)
  device.thread:call_with_delay(20, function() v3.show_stored_monthly(device) end)
  local timer = device.thread:call_on_schedule(POLL_SECONDS, function() v3.read_all(device, false) end, "v3_info_poll")
  device:set_field(TIMER_FIELD, timer, {persist = false})
  log.info("v3: 추가 정보 표시 시작 (" .. POLL_SECONDS .. "초마다 확인)")
end

return v3
