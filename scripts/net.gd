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
var bests: Dictionary = {}
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
	bests = res.get("bests", {})
	Save.set_session(nick, token)
	session_changed.emit()


func _clear_session() -> void:
	nick = ""
	token = ""
	school = ""
	bests = {}
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
	return res


func board(kind: String) -> Dictionary:
	return await call_api("board", {"kind": kind, "nick": nick})


func save_state(p_school: String) -> Dictionary:
	school = p_school
	return await call_api("saveState", {"state": {"school": p_school}})


func send_feedback(type: String, where: String, comment: String) -> Dictionary:
	return await call_api("feedback", {"type": type, "where": where, "comment": comment, "device": device()})


func log_event(kind: String, message: String, where: String, detail: String = "") -> void:
	if logged_in():
		call_api("log", {"kind": kind, "message": message, "where": where, "detail": detail, "device": device()})
