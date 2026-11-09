# 실기 채점관 (forklift-sim)

Korean practical-test grader for two licences, iOS, Godot 4.7.2 (Mobile), landscape.

- 지게차운전기능사 실기 "코스운전 및 작업": course and disqualification rules from the
  Q-Net public exam (posted 2025-12-22, `research/qnet_forklift_public_exam.pdf`, not shipped).
- 1종 특수 견인 (대형·소형·구난) 장내기능시험, graded by 도로교통법 시행규칙 별표24 (2026-02-24): `towing/`.
- Bundle com.yubinapps.forkliftsim. Korean and English (`scripts/lang.gd`, `towing/scripts/tow_lang.gd`).

## Forklift
- `data/course.json` the drawing's dimensions in multiples of D (vehicle width); D = 1.2 m for this
  forklift. Ring R 9.4D / 7.2D, arms 2.2D, box 2.4D x (4.0+2.0+3.0+3.0)D, stub 2.2D, 표준 파렛트 a/2
  past the 화물하차선. Corner fillets at the box opening are simplified; drum size is an estimate.
- `scripts/course.gd` drivable area, work zones (①, ②, parking, travel), painted edges.
- `scripts/sim.gd` driving (rear-wheel steer), forks, pallets and grading. Every disqualification
  records the measured value and the limit (fork height, line overshoot, offset, insertion, time).
- `scripts/exam_rules.gd` the 18 disqualification rows (16 measured by the app) and the estimated
  deductions. The public exam publishes only 상차 45 / 하차 55, so deductions are labelled estimates.
- `scripts/drills.gd` six course stages and one drill per rule (rulebook rows open them).
- `scripts/route.gd` the drawing's forward/reverse lines (plan drawing and test driver).
- `scripts/main.gd` home (two exam cards), exam-day mode (whistle, 1-minute start window, front-wheel
  timer, hard stop at 4:00), examiner HUD, freeze frame with measurement line and rewind, score sheet.
- `scripts/exam_unlock.gd` purchase wrapper; `PAYWALL := false` for 1.0 (everything free, no purchase UI).

## Tests (headless)
```
godot --headless --path . --audio-driver Dummy --script res://tests/test_sim.gd     # course + full autopilot run
godot --headless --path . --audio-driver Dummy --script res://tests/test_rules.gd   # each limit, timer, rule drills
godot --headless --path . --audio-driver Dummy --script res://tests/test_lang.gd    # KO/EN table completeness
godot --headless --path . --audio-driver Dummy --script res://towing/tests/test_exam.gd   # and test_rules, test_drills, test_audio, test_screens
```

## Screenshots
Never on a desktop window: `.github/workflows/shots.yml` renders in xvfb with the app's own debug-only
`shot=` argument, e.g. `fl_menu scene=menu; fl_rules_en scene=rules lang=en; fl_freeze scene=freeze rule=r14;
fl_sheet scene=result stop=99; t_home app=towing time=3`.
