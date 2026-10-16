class_name Iap
extends Node
## One-time "전체 해제" purchase (full course + mock exam) through StoreKit 2
## (ios/plugins/ios-in-app-purchase, hrk4649/godot_ios_plugin_iap 0.4.0).
## Without the plugin (desktop, web, tests) everything is open, unless the run
## argument locked=1 asks for the free version.

signal changed(unlocked: bool)
signal price_known(price: String)
signal failed()

const PRODUCT := "com.yubinapps.forkliftsim.unlock"

var unlocked := false
var price := ""
var _sk: Object
var _store: Store


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
	else:
		unlocked = not force_locked


func buy() -> void:
	if _sk:
		_sk.request("purchase", {"productID": PRODUCT})
	else:
		_set_unlocked(true)


func restore() -> void:
	if _sk:
		_sk.request("appStoreSync", {})
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


func _set_unlocked(on: bool) -> void:
	if _store:
		_store.data.unlocked = on
		_store.save()
	if on != unlocked:
		unlocked = on
		changed.emit(on)
