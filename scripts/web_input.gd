class_name WebInput
extends RefCounted
## 手机 / 平板网页版的文字输入：Godot 画在 canvas 里的输入框，iOS Safari 弹不出系统键盘。
## 做法：触屏设备上点输入框 → 弹出页面里的真 <input>（见 tools/web_head.html 的 qxEdit），用户点它就会出键盘；确定后把文字写回 LineEdit。
## 桌面浏览器 / 非网页版不受影响（直接用 LineEdit 自己的输入）。

static var _keep: Array = []
static var _busy := false


static func needed() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("typeof window.qxEdit === 'function' && window.qxCoarse()"))


static func attach(le: LineEdit, title: String) -> void:
	if not needed():
		return
	le.virtual_keyboard_enabled = false
	le.gui_input.connect(func(ev: InputEvent) -> void:     # 只在用户真的点了输入框时弹出（程序自动聚焦不触发，避免循环）
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			le.accept_event()
			_open(le, title)
	)


static func _open(le: LineEdit, title: String) -> void:
	if _busy:
		return
	_busy = true
	var cb := JavaScriptBridge.create_callback(func(args: Array) -> void:
		_busy = false
		if args.size() >= 2 and int(args[0]) == 1 and is_instance_valid(le):
			le.text = str(args[1])
			le.text_changed.emit(le.text)
	)
	_keep = [cb]
	var shown: Variant = JavaScriptBridge.get_interface("window").qxEdit(title, le.text, le.secret, le.max_length, cb)
	if shown != true:
		_busy = false
