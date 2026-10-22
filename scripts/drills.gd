class_name Drills
extends RefCounted
## 단계 드릴: 코스 한 구간만 반복 연습. Sim.start_drill()에 넘기는 시작 상태.

const REACH := Sim.CARRIAGE + Sim.FORK_LEN - Sim.PALLET * 0.5   # 앞축 → 팔레트 중심(완전 삽입)


static func list(c: Course) -> Array:
	var bx := c.back_line_x - (Sim.CARRIAGE + Sim.FORK_LEN * 0.5)
	return [
		{
			id = "start", title = "출발 준비", free = true,
			desc = "안전벨트 → 주차 브레이크 해제 → 포크 20~30cm → 출발선 통과",
			tip = "출발 신호 뒤 1분 안에 출발선을 지나야 해요. 포크가 50cm를 넘으면 실격.",
			pos = c.start_pos, heading = c.start_heading, lift = 0.0, step = Sim.Step.READY, goal = Sim.Step.TO_LOAD,
			seatbelt = false, park_brake = true,
		},
		{
			id = "load", title = "팔레트 상차", free = true,
			desc = "드럼 위 팔레트에 포크를 끝까지 넣고 들어 올리기",
			tip = "포크 높이를 드럼 윗면(90cm)보다 조금 높게 맞추고 천천히 전진. 20cm 넘게 덜 넣으면 실격.",
			pos = Vector2(0.0, 6.2), heading = PI / 2, lift = 0.25, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED,
		},
		{
			id = "forward", title = "전진 코스·하역", free = false,
			desc = "화물을 싣고 전진 코스를 돌아 하역 표시선 안에 내려놓기",
			tip = "틸트를 뒤로 젖히고 포크 20~30cm. 바퀴가 선을 밟으면 실격, 표시선에서 20cm 넘게 어긋나도 실격.",
			pos = Vector2(0.0, 5.6), heading = PI / 2, lift = 0.25, tilt = 4.0, carried = true, step = Sim.Step.LOADED, goal = Sim.Step.UNLOADED,
		},
		{
			id = "touch", title = "후진선 터치", free = false,
			desc = "후진해서 포크 가운데를 후진선에 맞추고, 중립 → 포크 바닥에 대기",
			tip = "완전히 선 다음 기어를 중립에 두고 포크를 내려요. 움직이며 내리거나 기어를 넣은 채 내리면 감점.",
			pos = Vector2(c.unload_target.x - REACH, c.unload_target.y), heading = 0.0, lift = 0.04, step = Sim.Step.UNLOADED, goal = Sim.Step.TOUCHED,
			pallet = c.unload_target, pallet_heading = c.unload_heading, pallet_base = 0.0, engaged = true,
		},
		{
			id = "reverse", title = "재상차·후진 코스", free = false,
			desc = "팔레트를 다시 싣고 후진으로 코스를 돌아 드럼 위에 내려놓기",
			tip = "후진 중에는 뒤 보기 버튼으로 뒤를 확인하세요. 드럼 위 20cm 안에 정확히.",
			pos = Vector2(bx, c.unload_target.y), heading = 0.0, lift = 0.0, step = Sim.Step.TOUCHED, goal = Sim.Step.RETURNED,
			pallet = c.unload_target, pallet_heading = c.unload_heading, pallet_base = 0.0,
		},
		{
			id = "park", title = "복귀·주차", free = false,
			desc = "후진으로 출발선을 지나 중립, 포크 바닥, 주차 브레이크",
			tip = "출발선을 뒤로 완전히 지난 뒤 멈추고 중립 → 포크 내림 → 주차 브레이크 순서.",
			pos = Vector2(0.0, 8.0), heading = PI / 2, lift = 0.25, step = Sim.Step.RETURNED, goal = Sim.Step.PARKED,
			pallet = c.pallet_start, pallet_heading = c.pallet_start_heading, pallet_base = c.drum_height,
		},
	]
