extends Node
## 在线账号 / 排行榜 / 反馈（Autoload: Net）。后端是 Google Apps Script + Google 表格（见 backend/）。
## api_url 为空时一切在线功能关闭，游戏照常单机玩（游客）。
##
## 网页版调试：在地址后加 ?api=<后端地址> 可临时覆盖 data/config.json 里的 api_url。
## 读取类请求（ping / board）用 GET；其余用 POST，Content-Type: text/plain（避免浏览器 CORS 预检）。

signal session_changed

const TIMEOUT := 12.0
const GET_ACTIONS := ["ping", "board"]

var api_url := ""
var nick := ""
var token := ""
var school := ""
var invite := ""        # 注册时用的邀请码（决定所属群）
var group_name := ""    # 所属群的名称（邀请表里的「名称」）
var bests: Dictionary = {}
var exp := 0            # 修为（服务器为准）
var alloc: Dictionary = {}   # 属性点分配
var talents: Dictionary = {} # 天赋加点
var items: Array = []        # 背包（装备编码，服务器发放）
var equip: Dictionary = {}   # 已穿戴：部位 → 编码
var silver := 0              # 银两（服务器为准）
var enh: Dictionary = {}     # 强化等级：编码 → 级数
## 测试注入：func(is_get: bool, url: String, body: Dictionary) -> Dictionary
var transport: Callable = Callable()


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var path := "res://data/config.json"
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.open(path, FileAccess.READ).get_as_text()) == OK and json.data is Dictionary:
			api_url = str((json.data as Dictionary).get("api_url", "")).strip_edges()
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('api') || ''")
		if q != null and str(q) != "":
			api_url = str(q)
		# 仅限开发：后端指向本机时，允许 ?speed=N 加快游戏用于端到端测试（线上地址不会启用）
		if api_url.begins_with("http://localhost") or api_url.begins_with("http://127.0.0.1"):
			var sp: Variant = JavaScriptBridge.eval("parseFloat(new URLSearchParams(location.search).get('speed') || '1')")
			if sp != null and float(sp) > 1.0:
				Engine.time_scale = minf(float(sp), 10.0)


func configured() -> bool:
	return api_url != ""


func logged_in() -> bool:
	return token != ""


## 没有配置在线服务时：桌面版（编辑器 / 本地调试）允许离线单机；网页版必须登录，
## 唯一的例外是后端还没部署时，管理员可以在地址后加 ?offline=1 自己试玩（存档只在本机；后端配置好之后这个入口不再生效）。
func offline_allowed() -> bool:
	if not OS.has_feature("web"):
		return true
	var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('offline') || ''")
	return q != null and str(q) == "1"


func device() -> String:
	return "%s %s" % [OS.get_name(), Engine.get_version_info()["string"]]


func _err(code: String, msg: String) -> Dictionary:
	return {"ok": false, "err": code, "msg": msg}


# ---------------------------------------------------------------------
# 传输
# ---------------------------------------------------------------------

func call_api(action: String, payload: Dictionary = {}) -> Dictionary:
	if not configured():
		return _err("offline", "未配置在线服务")
	var body := payload.duplicate()
	body["action"] = action
	if logged_in() and not body.has("nick") and not GET_ACTIONS.has(action) and action != "login" and action != "register":
		body["nick"] = nick
		body["token"] = token
	var is_get := GET_ACTIONS.has(action)
	if transport.is_valid():
		return await transport.call(is_get, api_url, body)
	return await _http(is_get, body)


func _http(is_get: bool, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var url := api_url
	var headers := PackedStringArray()
	var method := HTTPClient.METHOD_POST
	var data := ""
	if is_get:
		var parts: PackedStringArray = []
		for k in body:
			parts.append("%s=%s" % [str(k).uri_encode(), str(body[k]).uri_encode()])
		url += ("&" if "?" in url else "?") + "&".join(parts)
		method = HTTPClient.METHOD_GET
	else:
		headers.append("Content-Type: text/plain;charset=utf-8")   # 简单请求，不触发 CORS 预检
		data = JSON.stringify(body)
	if http.request(url, headers, method, data) != OK:
		http.queue_free()
		return _err("net", "网络请求失败")
	var r: Array = await http.request_completed   # [result, code, headers, body]
	http.queue_free()
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) >= 400:
		return _err("net", "网络连接失败，请稍后再试")
	var json := JSON.new()
	var text: String = (r[3] as PackedByteArray).get_string_from_utf8()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _err("net", "服务器返回了意外的内容")
	return json.data


# ---------------------------------------------------------------------
# 账号
# ---------------------------------------------------------------------

func _apply_profile(res: Dictionary) -> void:
	nick = str(res.get("nick", ""))
	token = str(res.get("token", ""))
	school = str(res.get("school", ""))
	invite = str(res.get("invite", ""))
	group_name = str(res.get("group", ""))
	bests = res.get("bests", {})
	exp = int(res.get("exp", 0))
	alloc = Meta.clean_alloc(res.get("alloc", {}))
	talents = Talents.clean(res.get("talents", {}))
	items = _codes(res.get("items", []))
	equip = res.get("equip", {}) if res.get("equip", {}) is Dictionary else {}
	silver = int(res.get("silver", 0))
	enh = res.get("enh", {}) if res.get("enh", {}) is Dictionary else {}
	Save.set_session(nick, token)
	session_changed.emit()


func _codes(v: Variant) -> Array:
	var out := []
	if v is Array:
		for c in v:
			out.append(str(c))
	return out


func _clear_session() -> void:
	nick = ""
	token = ""
	school = ""
	invite = ""
	group_name = ""
	bests = {}
	exp = 0
	alloc = {}
	talents = {}
	items = []
	equip = {}
	silver = 0
	enh = {}
	Save.clear_session()
	session_changed.emit()


func register(p_nick: String, pin: String, code: String) -> Dictionary:
	var res := await call_api("register", {"nick": p_nick, "pin": pin, "code": code, "device": device()})
	if bool(res.get("ok", false)):
		_apply_profile(res)
	return res


func login(p_nick: String, pin: String) -> Dictionary:
	var res := await call_api("login", {"nick": p_nick, "pin": pin, "device": device()})
	if bool(res.get("ok", false)):
		_apply_profile(res)
	return res


## 用保存的令牌自动登录；令牌失效时清掉本地会话（网络问题不清，下次再试）
func resume() -> Dictionary:
	var s := Save.session()
	if s.is_empty():
		return _err("no_session", "没有保存的登录")
	nick = str(s["nick"])
	token = str(s["token"])
	var res := await call_api("resume")
	if bool(res.get("ok", false)):
		_apply_profile(res)
	elif str(res.get("err", "")) != "net":
		_clear_session()
	else:
		nick = ""
		token = ""
	return res


func logout() -> void:
	if logged_in():
		await call_api("logout")
	_clear_session()


# ---------------------------------------------------------------------
# 成绩 / 排行榜 / 存档 / 反馈 / 日志
# ---------------------------------------------------------------------

func submit_run(summary: Dictionary) -> Dictionary:
	var body := summary.duplicate()
	body["build"] = JSON.stringify(summary.get("build", []))
	body["device"] = device()
	var res := await call_api("submit", body)
	if bool(res.get("ok", false)):
		bests = res.get("bests", bests)
		exp = int(res.get("exp", exp))
		silver = int(res.get("silver", silver))
	return res


## group_only：只看自己所属群（邀请码相同的玩家）
func board(kind: String, group_only: bool = false) -> Dictionary:
	var body := {"kind": kind, "nick": nick}
	if group_only and invite != "":
		body["group"] = invite
	return await call_api("board", body)


func save_state(p_school: String) -> Dictionary:
	school = p_school
	return await call_api("saveState", {"state": {"school": p_school}})


## 保存属性点分配（服务器会校验总点数不超过已获得的点数）
func save_alloc(p_alloc: Dictionary) -> Dictionary:
	var res := await call_api("saveState", {"state": {"school": Save.school(), "alloc": Meta.clean_alloc(p_alloc)}})
	if bool(res.get("ok", false)):
		alloc = Meta.clean_alloc(p_alloc)
	return res


func save_talents(t: Dictionary) -> Dictionary:
	var res := await call_api("saveState", {"state": {"school": Save.school(), "talents": Talents.clean(t)}})
	if bool(res.get("ok", false)):
		talents = Talents.clean(t)
	return res


## 穿戴 / 丢弃装备；成功时以服务器返回的背包和穿戴为准
func save_gear(p_equip: Dictionary, discard: Array) -> Dictionary:
	var st := {"school": Save.school(), "equip": p_equip}
	if not discard.is_empty():
		st["discard"] = discard
	var res := await call_api("saveState", {"state": st})
	if bool(res.get("ok", false)):
		items = _codes(res.get("items", items))
		equip = res.get("equip", p_equip)
		silver = int(res.get("silver", silver))
		enh = res.get("enh", enh) if res.get("enh", enh) is Dictionary else enh
	return res


## 铁匠强化一件装备（服务器扣银两、记录等级）
func enhance(code: String) -> Dictionary:
	var res := await call_api("enhance", {"code": code})
	if bool(res.get("ok", false)):
		silver = int(res.get("silver", silver))
		enh = res.get("enh", enh) if res.get("enh", enh) is Dictionary else enh
	return res


func send_feedback(type: String, where: String, comment: String) -> Dictionary:
	return await call_api("feedback", {"type": type, "where": where, "comment": comment, "device": device()})


func log_event(kind: String, message: String, where: String, detail: String = "") -> void:
	if logged_in():
		call_api("log", {"kind": kind, "message": message, "where": where, "detail": detail, "device": device()})
