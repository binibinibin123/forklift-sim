class_name Onboarding
extends Control
## Three cards on first launch: what the app is, how to drive, what's free.

signal done

const PAGES := [
	{"title": "견인 기능시험 3D", "body": "1종 특수면허 기능시험(소형견인·구난·대형견인)을 실제 채점 기준으로 연습하는 3D 시험장이에요.\n굴절·곡선·방향전환 코스와 연결·분리 작업을 모두 담았어요."},
	{"title": "조작은 이렇게", "body": "왼쪽 핸들을 돌려 조향하고, 오른쪽 가속·브레이크 페달과 D/R 기어로 움직여요.\n운전석 시점에서는 사이드미러가 보이고, 궤적선과 히치각 게이지가 트레일러 후진을 도와줘요."},
	{"title": "코치와 함께", "body": "코스마다 코치가 상황에 맞게 조언하고, 끝나면 리플레이로 실수한 순간을 다시 볼 수 있어요.\n소형견인 굴절·곡선 코스와 직진 후진 훈련은 무료예요."},
]

var page := 0
var title_lbl: Label
var body_lbl: Label
var dots: HBoxContainer
var next_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var p := Kit.panel(Kit.BG_SOLID, 26, 28)
	cc.add_child(p)
	var v := Kit.vbox(14)
	v.custom_minimum_size = Vector2(680, 0)
	p.add_child(v)
	title_lbl = Kit.label("", 36, Kit.PRIMARY)
	v.add_child(title_lbl)
	body_lbl = Kit.wrap("", 22, Kit.TEXT, 680)
	v.add_child(body_lbl)
	var row := Kit.hbox(10)
	v.add_child(row)
	dots = Kit.hbox(6)
	row.add_child(dots)
	row.add_child(Kit.spacer())
	row.add_child(Kit.button("건너뛰기", func(): done.emit(), 19, "ghost"))
	next_btn = Kit.button("다음", _next, 22, "primary")
	row.add_child(next_btn)
	_show(0)


func _show(i: int) -> void:
	page = i
	title_lbl.text = PAGES[i].title
	body_lbl.text = PAGES[i].body
	for c in dots.get_children():
		c.queue_free()
	for k in PAGES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.color = Kit.PRIMARY if k == i else Color(1, 1, 1, 0.25)
		dots.add_child(d)
	next_btn.text = "시작하기" if i == PAGES.size() - 1 else "다음"


func _next() -> void:
	if page + 1 >= PAGES.size():
		done.emit()
	else:
		_show(page + 1)
