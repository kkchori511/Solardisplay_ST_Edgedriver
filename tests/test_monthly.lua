-- 월 누적 전력량 계산(v3_info.lua) 시험. 실행: cd drivers/solar-power-meter && lua ../../tests/test_monthly.lua
package.path = "src/?.lua;" .. package.path
local function cap(name, attr) return {[attr] = function(t) return {cap=name, attr=attr, v=t.value, u=t.unit} end} end
package.loaded["st.capabilities"] = {voltageMeasurement=cap("v","voltage"), currentMeasurement=cap("c","current"), temperatureMeasurement=cap("t","temperature"), energyMeter=cap("energyMeter","energy")}
package.loaded["st.zigbee.constants"] = {SIMPLE_METERING_MULTIPLIER_KEY="m", SIMPLE_METERING_DIVISOR_KEY="d"}
local function attrs(t) local r = {} for k,id in pairs(t) do r[k] = {ID=id, read=function() return k end} end return {attributes=r} end
local EM = attrs{RMSVoltage=1,RMSCurrent=2,ACFrequency=3,PowerFactor=4,ACVoltageMultiplier=5,ACVoltageDivisor=6,ACCurrentMultiplier=7,ACCurrentDivisor=8}; EM.ID=0xB04
local SM = attrs{CurrentSummationDelivered=0}; SM.ID=0x702
local TM = attrs{MeasuredValue=0}; TM.ID=0x402
package.loaded["st.zigbee.zcl.clusters"] = {ElectricalMeasurement=EM, SimpleMetering=SM, TemperatureMeasurement=TM}
package.loaded["log"] = {info=function() end, warn=print}
local v3 = require "shinasystems.v3_info"
local fails = 0
local function eq(name, got, want)
  local ok = (type(got)=="number" and type(want)=="number") and math.abs(got-want) < 1e-9 or got == want
  if not ok then fails = fails + 1; print("FAIL", name, "got", tostring(got), "want", tostring(want)) else print("ok  ", name, tostring(got)) end
end
-- 시스템 시간대와 무관하게 KST 시각의 epoch를 만든다
local function at(y,m,d,h,mi,s)
  local days = (os.time({year=y,month=m,day=d,hour=12}) - os.time({year=1970,month=1,day=1,hour=12})) / 86400
  return math.floor(days) * 86400 + h*3600 + mi*60 + (s or 0) - 9*3600
end
-- 연월 (한국 시간)
eq("10/31 23:59:59 KST", v3.month_key(at(2026,10,31,23,59,59)), 202610)
eq("11/01 00:00:00 KST", v3.month_key(at(2026,11,1,0,0,0)), 202611)
eq("UTC로는 아직 10월 31일 15:00", v3.month_key(at(2026,11,1,0,0,0) - 1), 202610)
eq("연말 12/31 23:59 -> 1/1 00:00", v3.month_key(at(2026,12,31,23,59,59)), 202612)
eq("연말 넘김", v3.month_key(at(2027,1,1,0,0,0)), 202701)
-- 순수 계산
local s, m = v3.monthly_next({}, 202610, 5706.7);               eq("처음: 시작값=지금, 누적 0", m, 0); eq("  base", s.base, 5706.7)
s, m = v3.monthly_next(s, 202610, 5710.2);                      eq("같은 달 증가", m, 3.5)
s, m = v3.monthly_next(s, 202610, 5712.0);                      eq("같은 달 더 증가", m, 5.3); eq("  base 그대로", s.base, 5706.7)
s, m = v3.monthly_next(s, 202611, 5712.0);                      eq("달 바뀜(밤이라 값 같음): 0부터", m, 0); eq("  새 base=직전값", s.base, 5712.0)
s, m = v3.monthly_next(s, 202611, 5713.4);                      eq("11월 증가", m, 1.4)
s, m = v3.monthly_next({key=202610, base=100, last=150}, 202611, 150.4); eq("달 바뀐 뒤 첫 보고가 조금 늦어도", m, 0.4)
s, m = v3.monthly_next({key=202611, base=500, last=520}, 202611, 40);    eq("기기 초기화(값 감소): 새 시작값", m, 0); eq("  base=40", s.base, 40)
s, m = v3.monthly_next({key=202610, base=100, last=nil}, 202611, 130);   eq("직전값이 없으면 지금부터", m, 0)
s, m = v3.monthly_next({key=202610, base=100, last=200}, 202611, 150);   eq("직전값이 지금보다 크면(이상) 지금부터", m, 0)
s, m = v3.monthly_next({key=202612, base=900, last=950}, 202701, 950);   eq("연말에서 연초", m, 0)
-- 가짜 기기: 저장 필드와 재시작
local function device()
  local d = {persist = {}, mem = {}, out = {}, profile = {components = {monthly = "MONTHLY"}}}
  function d:get_field(k) if self.mem[k] ~= nil then return self.mem[k] end return self.persist[k] end
  function d:set_field(k, v, o) if o and o.persist then self.persist[k] = v else self.mem[k] = v end end
  function d:emit_component_event(c, e) e.component = c; self.out[#self.out+1] = e end
  return d
end
local d = device()
v3.update_monthly(d, 5706.714, at(2026,10,18,14,0,0)); eq("기기: 첫 보고 0", d.out[#d.out].v, 0); eq("  컴포넌트", d.out[#d.out].component, "MONTHLY")
v3.update_monthly(d, 5709.0,   at(2026,10,18,14,7,30)); eq("기기: 증가", d.out[#d.out].v, 2.286)
v3.update_monthly(d, 5712.3,   at(2026,10,18,18,0,0));  eq("기기: 저녁까지", d.out[#d.out].v, 5.586)
eq("저장된 key", d.persist.monthly_key, 202610); eq("저장된 base", d.persist.monthly_base, 5706.714)
-- 드라이버 재시작: 메모리 필드는 사라지고 저장된 값만 남는다
local d2 = device(); d2.persist = d.persist
v3.update_monthly(d2, 5712.3, at(2026,10,19,6,0,0));    eq("재시작 후 이어서", d2.out[#d2.out].v, 5.586)
-- 월말 -> 월초 (밤 사이, 보고가 계속 옴)
v3.update_monthly(d2, 5800.0, at(2026,10,31,17,0,0));   eq("월말 누적", d2.out[#d2.out].v, 93.286)
v3.update_monthly(d2, 5800.0, at(2026,10,31,23,55,0));  eq("자정 직전", d2.out[#d2.out].v, 93.286)
v3.update_monthly(d2, 5800.0, at(2026,11,1,0,5,0));     eq("자정 직후: 0으로 리셋", d2.out[#d2.out].v, 0)
eq("  새 월 key", d2.persist.monthly_key, 202611); eq("  새 base", d2.persist.monthly_base, 5800.0)
v3.update_monthly(d2, 5801.2, at(2026,11,1,9,0,0));     eq("11월 첫 발전", d2.out[#d2.out].v, 1.2)
-- 프로필에 monthly 컴포넌트가 없으면 이벤트 없음(상태는 갱신)
local d3 = device(); d3.profile = {components = {}}
v3.update_monthly(d3, 100, at(2026,10,18,14,0,0)); eq("컴포넌트 없음: 이벤트 없음", #d3.out, 0); eq("  상태는 저장", d3.persist.monthly_base, 100)
-- 시작할 때 저장값 표시
local d4 = device(); d4.persist = {monthly_key=202610, monthly_base=100, monthly_last=130.5}
local real_time = os.time; os.time = function(t) if t then return real_time(t) end return at(2026,10,25,12,0,0) end
v3.show_stored_monthly(d4); eq("시작 시 저장값 표시", d4.out[1] and d4.out[1].v, 30.5)
local d5 = device(); d5.persist = {monthly_key=202609, monthly_base=100, monthly_last=130.5}
v3.show_stored_monthly(d5); eq("지난 달 값은 표시 안 함", #d5.out, 0)
os.time = real_time
print(fails == 0 and "모두 통과" or (fails .. "개 실패"))
