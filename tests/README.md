# 드라이버 로컬 시험

허브 없이 맥에서 Lua로 계산 부분을 시험한다 (`brew install lua`). 허브 API는 가짜(stub)로 대체한다.
반드시 드라이버 폴더에서 실행한다 (상대 경로 `src/`를 읽는다).

```
cd drivers/solar-power-meter
lua ../../tests/test_monthly.lua   # 월 누적 전력량: 달 경계(한국 시간), 연말, 재시작, 기기 초기화 등 36개 항목, 마지막 줄 "모두 통과"
lua ../../tests/test_clock.lua     # 시계로 보내는 본문(구간별 색, 막대, W 글자 위치)을 여러 값으로 출력해 눈으로 확인
```

- 이 시험은 `drivers/` 밖에 있어 허브에 올라가는 패키지에 들어가지 않는다.
- 새 계산 코드를 만들면 같은 방식으로 시험을 먼저 만든다 (순수 함수로 분리해 두면 쉽다).
- 시계 화면 배치는 TC001 레포의 `scripts/preview-weather.sh`와 `scripts/show-screen.py`로 실제 시계에서 확인한다.
