-- 시하스 V3 드라이버가 보여주던 정보를 표시한다: 전압, 전류, 주파수, 역률, 온도, 생산(역방향) 누적량.
-- 배율은 기기에게 직접 물어 확인한 값이다 (2026-10-18 허브 로그):
--   전압 /10 (ACVoltageDivisor=10), 전류 /100 (ACCurrentDivisor=100), 전력 /1,
--   주파수 0x0259=601 -> 60.1Hz (/10, 기기는 배율 속성을 지원하지 않음),
--   온도 /100 (2423 -> 24.23C), 누적량 /1000 (SimpleMetering Divisor=1000), 역률은 % 그대로.
-- 생산(역방향) 누적량은 SimpleMetering 표준 속성 0x0001(CurrentSummationReceived)이다.
-- 이 라이브러리에는 그 이름이 없어 번호로 읽고 받는다.

local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local log = require "log"

local EM = clusters.ElectricalMeasurement
local SM = clusters.SimpleMetering
local TM = clusters.TemperatureMeasurement

local v3 = {}

v3.PROFILE = "sihas-solar-v3"
v3.SUMMATION_RECEIVED_ID = 0x0001

local FREQUENCY_CAPABILITY = "afterguide46998.frequencyMeasurement"
local POWER_FACTOR_CAPABILITY = "afterguide46998.powerfactorMeasurement"

local POLL_SECONDS = 120
local TIMER_FIELD = "v3_info_timer"
local PROFILE_FIELD = "v3_profile_requested"

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

function v3.produced_handler(driver, device, value, zb_rx)
  local components = device.profile and device.profile.components
  local component = components and components.produced
  if component == nil then return end
  local mult = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local div = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1000
  device:emit_component_event(component, capabilities.energyMeter.energy({value = value.value * mult / div, unit = "kWh"}))
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
    [SM.ID] = {
      [v3.SUMMATION_RECEIVED_ID] = v3.produced_handler,
    },
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
  local ok, err = pcall(function()
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(SM.ID), data_types.AttributeId(v3.SUMMATION_RECEIVED_ID)))
  end)
  if not ok then log.warn("v3: 생산량 읽기 실패 " .. tostring(err)) end
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
  local timer = device.thread:call_on_schedule(POLL_SECONDS, function() v3.read_all(device, false) end, "v3_info_poll")
  device:set_field(TIMER_FIELD, timer, {persist = false})
  log.info("v3: 추가 정보 표시 시작 (" .. POLL_SECONDS .. "초마다 확인)")
end

return v3
