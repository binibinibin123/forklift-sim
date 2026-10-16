class_name Iap
extends Node
## One-time "전체 해제" purchase (full course + mock exam) through StoreKit 2
## (ios/plugins/ios-in-app-purchase, hrk4649/godot_ios_plugin_iap 0.4.0).
## In the Toss mini-app (web build) the page's window.aitBridge talks to the
## Apps in Toss IAP SDK instead (toss/src/bridge.js).
## Without either (desktop, plain web, tests) everything is open, unless the run
## argument locked=1 asks for the free version.

signal changed(unlocked: bool)
signal price_known(price: String)
signal failed()

const PRODUCT := "com.yubinapps.forkliftsim.unlock"

var unlocked := false
var price := ""
var _sk: Object
var _store: Store
var _js: JavaScriptObject
var _js_cb: JavaScriptObject   # keep a reference or the callback is freed


func setup(store: Store, force_locked: bool) -> void:
	_store = store
	if Engine.has_singleton("IOSInAppPurchase"):
		unlocked = bool(store.data.get("unlocked", false))
		_sk = Engine.get_singleton("IOSInAppPurchase")
		_sk.response.connect(_on_response)
		_sk.request("startUpdateTask", {})
		_sk.request("proceedUnfinishedTransactions", {})
		_sk.request("products", {"productIDs": [PRODUCT]})
		_sk.request("transactionCurrentEntitlements", {})
	elif OS.has_feature("web") and JavaScriptBridge.eval("typeof window.aitBridge === 'object'", true):
		unlocked = bool(store.data.get("unlocked", false))
		_js = JavaScriptBridge.get_interface("aitBridge")
		_js_cb = JavaScriptBridge.create_callback(_on_js)
		_js.init(_js_cb)
	else:
		unlocked = not force_locked


func buy() -> void:
	if _sk:
		_sk.request("purchase", {"productID": PRODUCT})
	elif _js:
		_js.buy()
	else:
		_set_unlocked(true)


func restore() -> void:
	if _sk:
		_sk.request("appStoreSync", {})
	elif _js:
		_js.restore()
	else:
		_set_unlocked(true)


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
		"appStoreSync":
			_sk.request("transactionCurrentEntitlements", {})
			if not ok:
				failed.emit()
		"transactionCurrentEntitlements":
			if ok:   # only trust a real answer; offline keeps the saved state
				var owned := false
				for t in data.get("transactions", []):
					if str(t.get("productID", "")) == PRODUCT and str(t.get("revocationDate", "")) == "":
						owned = true
				_set_unlocked(owned)


## Events from toss/src/bridge.js, one JSON string each:
## {"type":"owned","value":bool} | {"type":"price","value":"5,500원"} | {"type":"failed"}
func _on_js(args: Array) -> void:
	var ev = JSON.parse_string(str(args[0])) if args.size() > 0 else null
	if typeof(ev) != TYPE_DICTIONARY:
		return
	match str(ev.get("type", "")):
		"owned":
			_set_unlocked(bool(ev.get("value", false)))
		"price":
			price = str(ev.get("value", ""))
			price_known.emit(price)
		"failed":
			failed.emit()


func _set_unlocked(on: bool) -> void:
	if _store:
		_store.data.unlocked = on
		_store.save()
	if on != unlocked:
		unlocked = on
		changed.emit(on)
