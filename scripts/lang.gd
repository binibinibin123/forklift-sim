class_name Lang
extends RefCounted
## Korean / English text for every screen.
## Korean is the default. On first run English is picked when the device
## language is not Korean; the setting (user://lang.json) wins afterwards.
## Forklift and shared keys live here; towing keys in towing/scripts/tow_lang.gd.
##
##   Lang.t("key")              -> text in the current language
##   Lang.t("key", [a, b])      -> text % [a, b]
##   Lang.is_en(), Lang.set_code("en")

const SAVE := "user://lang.json"
const CODES := ["ko", "en"]

static var code := ""
static var _tables := {}


static func current() -> String:
	if code == "":
		code = _initial()
	return code


static func is_en() -> bool:
	return current() == "en"


static func set_code(c: String) -> void:
	code = c if c in CODES else "ko"
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"lang": code}))


static func _initial() -> String:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("lang="):
				var c := a.substr(5)
				if c in CODES:
					return c
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary and str(d.get("lang", "")) in CODES:
			return str(d.lang)
	return "ko" if OS.get_locale_language() == "ko" else "en"


static func table(c: String) -> Dictionary:
	if _tables.is_empty():
		var ko := KO.duplicate()
		var en := EN.duplicate()
		ko.merge(TowLang.KO)
		en.merge(TowLang.EN)
		_tables = {"ko": ko, "en": en}
	return _tables.get(c, _tables.ko)


static func has(key: String) -> bool:
	return table("ko").has(key)


static func t(key: String, args = null) -> String:
	var s: String = table(current()).get(key, table("ko").get(key, key))
	if args != null:
		s = s % args
	return s


## Picks one of two strings by language, for text built from data rows.
static func pick(ko: String, en: String) -> String:
	return en if is_en() else ko


const KO := {
}

const EN := {
}
