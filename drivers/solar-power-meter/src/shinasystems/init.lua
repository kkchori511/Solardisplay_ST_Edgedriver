-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local configurations = require "configurations"
local clock = require "clock"
local log = require "log"
local v3_info = require "shinasystems.v3_info"


local POWERMETER_CONFIGURATION_V2 = {
  {
    cluster = SimpleMetering.ID,
    attribute = SimpleMetering.attributes.CurrentSummationDelivered.ID,
    minimum_interval = 5,
    maximum_interval = 450, -- Since the 15 minute report below depends on this report we make this 7.5 minutes
    data_type = SimpleMetering.attributes.CurrentSummationDelivered.base_type,
    reportable_change = 1
  },
  {
    cluster = SimpleMetering.ID,
    attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
    minimum_interval = 5,
    maximum_interval = 3600,
    data_type = SimpleMetering.attributes.InstantaneousDemand.base_type,
    reportable_change = 5
  },
  { -- reporting : no
    cluster = ElectricalMeasurement.ID,
    attribute = ElectricalMeasurement.attributes.ActivePower.ID,
    minimum_interval = 5,
    maximum_interval = 65535,
    data_type = ElectricalMeasurement.attributes.ActivePower.base_type,
    reportable_change = 5
  }
}


local function energy_meter_handler(driver, device, value, zb_rx)
  local multiplier = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1000
  local raw_value = value.value
  local raw_value_kilowatts = raw_value * multiplier/divisor

  local offset = device:get_field(constants.ENERGY_METER_OFFSET) or 0
  if raw_value_kilowatts < offset then
    --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
    offset = 0
    device:set_field(constants.ENERGY_METER_OFFSET, offset, {persist = true})
  end
  raw_value_kilowatts = raw_value_kilowatts - offset

  local raw_value_watts = raw_value_kilowatts*1000
  local delta_tick
  local last_save_ticks = device:get_field("LAST_SAVE_TICK")

  if last_save_ticks == nil then last_save_ticks = 0 end
  delta_tick = os.time() - last_save_ticks

  -- wwst energy certification : powerConsumptionReport capability values should be updated every 15 minutes.
  -- Check if 15 minutes have passed since the reporting time of current_power_consumption.
  if delta_tick >= 15*60 then
    local delta_energy = 0.0
    local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
    if current_power_consumption ~= nil then
      delta_energy = math.max(raw_value_watts - current_power_consumption.energy, 0.0)
    end
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value_watts, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

    local curr_save_tick = last_save_ticks + 15*60 -- Set the time to a regular interval by adding 15 minutes to the existing last_save_ticks.
    -- If the time 15 minutes from now is less than the current time, set the current time as the last time.
    if curr_save_tick + 15*60 < os.time() then
      curr_save_tick = os.time()
    end
    device:set_field("LAST_SAVE_TICK", curr_save_tick, {persist = false})
  end
  device:emit_event(capabilities.energyMeter.energy({value = raw_value_kilowatts, unit = "kWh"}))
  -- 월 누적 생산량 (이번 달 시작 시점의 누적값을 뺀 값)
  local ok, err = pcall(v3_info.update_monthly, device, raw_value_kilowatts)
  if not ok then log.warn("월 누적 계산 오류: " .. tostring(err)) end
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
  clock.start(device)
end

local device_init = function(self, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  for _, attribute in ipairs(POWERMETER_CONFIGURATION_V2) do
    device:add_configured_attribute(attribute)
  end
  -- 시계로 전력값 전송 시작 (Solardisplay_ST_TC001)
  clock.start(device)
  v3_info.start(device)
end

-- 기기의 드라이버를 이 드라이버로 교체하면 init이 다시 불리지 않을 수 있어 여기서도 시작한다.
local device_driver_switched = function(self, device)
  clock.start(device)
  v3_info.start(device)
end

local device_removed = function(self, device)
  clock.stop(device)
  v3_info.stop(device)
end

-- V3 정보(전압, 전류, 주파수, 역률, 온도, 생산량) 핸들러에 기존 누적(소비) 핸들러를 더한다
local attr_handlers = v3_info.attr_handlers()
attr_handlers[SimpleMetering.ID][SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler

local shinasystems_power_meter_handler = {
  NAME = "shinasystems power meter handler",
  zigbee_handlers = {
    attr = attr_handlers
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure,
    driverSwitched = device_driver_switched,
    removed = device_removed,
  },
  can_handle = require("shinasystems.can_handle"),
}

return shinasystems_power_meter_handler
