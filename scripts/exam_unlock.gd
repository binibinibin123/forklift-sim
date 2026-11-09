class_name ExamUnlock
extends Node
## Access to the full exam set (forklift mock exam + every towing exam).
##
## Version 1.0 ships with PAYWALL off: everything is open, no StoreKit request
## is made and no purchase screen is shown. The one-time purchase code below is
## kept for a later update and comes back by flipping PAYWALL to true.
##
## With PAYWALL on: StoreKit 2 on iOS (ios/plugins/ios-in-app-purchase,
## hrk4649/godot_ios_plugin_iap 0.4.0); in the Toss mini-app (web build) the
## page's window.aitBridge (toss/src/bridge.js). One instance lives under the
## tree root (ExamUnlock.shared()) so the forklift and towing scenes agree; the
## last answer is cached in its own file.

const PAYWALL := false

signal changed(unlocked: bool)
signal price_known(price: String)
signal failed()
signal settled()   # a purchase, restore or entitlement check finished

const CACHE := "user://unlock.json"
const PRODUCT := "com.yubinapps.forkliftsim.unlock"

var unlocked := true
var price := ""
var _sk: Object
static var _shared: ExamUnlock
var _js: JavaScriptObject
var _js_cb: JavaScriptObject   # keep a reference or the callback is freed


static func shared() -> ExamUnlock:
	if _shared == null:
		_shared = ExamUnlock.new()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_shared)
		var locked := false
		if OS.is_debug_build():
			for a in OS.get_cmdline_user_args():
				if a == "locked" or a.begins_with("locked="):
					locked = true
		_shared._start(locked)
	return _shared


## True when a purchase screen may be shown at all.
static func paywall_on() -> bool:
	return PAYWALL


func _start(force_locked: bool) -> void:
	if not PAYWALL:
		unlocked = true
		return
	if Engine.has_singleton("IOSInAppPurchase"):
		unlocked = _cached()
		_sk = Engine.get_singleton("IOSInAppPurchase")
		# The plugin emits from a StoreKit background thread; handle it on the main thread.
		_sk.response.connect(_on_response, CONNECT_DEFERRED)
		_sk.request("startUpdateTask", {})
		_sk.request("proceedUnfinishedTransactions", {})
		_sk.request("products", {"productIDs": [PRODUCT]})
		_sk.request("transactionCurrentEntitlements", {})
	elif OS.has_feature("web") and JavaScriptBridge.eval("typeof window.aitBridge === 'object'", true):
		unlocked = _cached()
		_js = JavaScriptBridge.get_interface("aitBridge")
		_js_cb = JavaScriptBridge.create_callback(_on_js)
		_js.init(_js_cb)
	else:
		unlocked = not force_locked


func _cached() -> bool:
	for path in [CACHE, ForkliftSave.PATH]:   # ForkliftSave.PATH held the cache before 2.0
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary and d.has("unlocked"):
				return bool(d.unlocked)
	return false


func buy() -> void:
	if not PAYWALL:
		settled.emit()
	elif _sk:
		_sk.request("purchase", {"productID": PRODUCT})
	elif _js:
		_js.buy()
	else:
		_set_unlocked(true)
		settled.emit()


func restore() -> void:
	if not PAYWALL:
		settled.emit()
	elif _sk:
		_sk.request("appStoreSync", {})
	elif _js:
		_js.restore()
	else:
		_set_unlocked(true)
		settled.emit()


func _on_response(name: String, data: Dictionary) -> void:
	var ok := str(data.get("result", "")) == "success"
	match name:
		"products":
			if ok:
				for p in data.get("products", []):
					if str(p.get("id", "")) == PRODUCT:
						price = str(p.get("displayPrice", ""))
						price_known.emit(price)
			else:
				get_tree().create_timer(10.0).timeout.connect(func(): _sk.request("products", {"productIDs": [PRODUCT]}))
		"purchase":
			if ok and str(data.get("productID", "")) == PRODUCT and str(data.get("revocationDate", "")) == "":
				_set_unlocked(true)
			elif not ok:
				failed.emit()
			settled.emit()
		"appStoreSync":
			_sk.request("transactionCurrentEntitlements", {})
			if not ok:
				failed.emit()
				settled.emit()
		"transactionCurrentEntitlements":
			if ok:   # only trust a real answer; offline keeps the saved state
				var owned := false
				for t in data.get("transactions", []):
					if str(t.get("productID", "")) == PRODUCT and str(t.get("revocationDate", "")) == "":
						owned = true
				_set_unlocked(owned)
			settled.emit()


## Events from toss/src/bridge.js, one JSON string each:
## {"type":"owned","value":bool} | {"type":"price","value":"5,500원"} | {"type":"failed"}
func _on_js(args: Array) -> void:
	var ev = JSON.parse_string(str(args[0])) if args.size() > 0 else null
	if typeof(ev) != TYPE_DICTIONARY:
		return
	match str(ev.get("type", "")):
		"owned":
			_set_unlocked(bool(ev.get("value", false)))
			settled.emit()
		"price":
			price = str(ev.get("value", ""))
			price_known.emit(price)
		"failed":
			failed.emit()
			settled.emit()


func _set_unlocked(on: bool) -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": on}))
	if on != unlocked:
		unlocked = on
		changed.emit(on)
