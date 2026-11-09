class_name Purchases
extends Node
## The towing screens' view of the app's single "전체 해제" purchase.
## The purchase itself lives in the shared ExamUnlock (res://scripts/exam_unlock.gd), so one
## unlock opens the forklift course and every towing exam. This node keeps the
## API the towing screens were written against: unlocked, price, busy, buy(),
## restore() and the changed / price_known / busy_changed / failed signals.

signal changed(unlocked: bool)
signal price_known(price: String)
signal busy_changed(busy: bool)
signal failed(reason: String)

var busy := false
var _iap: ExamUnlock


var unlocked: bool:
	get:
		return _iap != null and _iap.unlocked


var price: String:
	get:
		return _iap.price if _iap else ""


func setup(_store: TowStore, _force_locked: bool) -> void:
	# `locked` on the command line is read by ExamUnlock.shared() itself
	_iap = ExamUnlock.shared()
	_iap.changed.connect(_on_changed)
	_iap.price_known.connect(_on_price)
	_iap.failed.connect(_on_failed)
	_iap.settled.connect(_on_settled)


func buy() -> void:
	if busy:
		return
	_set_busy(true)
	_iap.buy()


func restore() -> void:
	if busy:
		return
	_set_busy(true)
	_iap.restore()


func _on_changed(on: bool) -> void:
	changed.emit(on)


func _on_price(p: String) -> void:
	price_known.emit(p)


func _on_failed() -> void:
	failed.emit("")


func _on_settled() -> void:
	_set_busy(false)


func _set_busy(b: bool) -> void:
	if b != busy:
		busy = b
		busy_changed.emit(b)
