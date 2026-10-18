-- 시계 전송 본문(clock.lua) 시험. 실행: cd drivers/solar-power-meter && lua ../../tests/test_clock.lua
package.path = "src/?.lua;" .. package.path
package.loaded["st.capabilities"] = {powerMeter = {ID="powerMeter", power={NAME="power"}}}
package.loaded["cosock"] = {asyncify = function() return {} end}
package.loaded["log"] = {warn=print, info=print}
package.loaded["ltn12"] = {}
local clock = require "clock"
for _, w in ipairs({0, 5, 45, 100, 850, 1500, 3200, 4200, 9999, 12345, -3.2}) do print(clock.build_body(w)) end
