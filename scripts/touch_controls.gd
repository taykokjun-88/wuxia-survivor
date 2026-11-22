class_name TouchControls
extends CanvasLayer
## 手机 / 平板触控：左半屏「浮动摇杆」+ 右下角技能键（轻功 / 真气爆发）+ 暂停 / 详情；村子里是摇杆 + 「交谈」+ 菜单。
## 只在触屏设备上出现（检测到触摸 / 系统报告有触屏）；一旦收到键盘按键就自动隐藏（笔记本触屏 + 键盘不会重复显示）。
## 坐标一律是游戏视口坐标（1280×720，随窗口等比缩放）。摇杆通过 Input.action_press 写进 move_* 动作，主循环不用改。

signal pause_pressed
signal detail_pressed
signal interact_pressed
signal menu_pressed

const STICK_R := 70.0
const DASH_POS := Vector2(1170, 596)
const DASH_R := 58.0
const ULT_POS := Vector2(1036, 640)
const ULT_R := 46.0
const PAUSE_POS := Vector2(1238, 262)
const DETAIL_POS := Vector2(1238, 322)
const SMALL_R := 24.0
const MENU_POS := Vector2(1238, 48)
const INTERACT_POS := Vector2(1170, 596)

var mode := ""                  # "" 不显示 / "play" 局内 / "town" 村子
var touch_seen := false
var keyboard_seen := false
var world: GameWorld = null
var town: Town = null
var move_vec := Vector2.ZERO

var _pad: Control
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch: Dictionary = {}     # touch index -> 按钮名


func _ready() -> void:
	layer = 20
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad)
	_pad.draw.connect(_draw_pad)


func is_active() -> bool:
	return mode != "" and not keyboard_seen and (touch_seen or DisplayServer.is_touchscreen_available())


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	_release_all()
	_pad.visible = m != ""


func _process(_dt: float) -> void:
	_pad.visible = is_active()
	if _pad.visible:
		_pad.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if not keyboard_seen:
			keyboard_seen = true
			_release_all()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_seen = true
		keyboard_seen = false
	if not is_active():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_idx:
			_stick_move(sd.position)


## 点中了哪个按钮（返回按钮名，没点中返回 ""）
func _hit(pos: Vector2) -> String:
	if mode == "play":
		if pos.distance_to(DASH_POS) <= DASH_R * 1.25:
			return "dash"
		if pos.distance_to(ULT_POS) <= ULT_R * 1.25:
			return "ult"
		if pos.distance_to(PAUSE_POS) <= SMALL_R * 1.4:
			return "pause"
		if pos.distance_to(DETAIL_POS) <= SMALL_R * 1.4:
			return "detail"
	elif mode == "town":
		if pos.distance_to(MENU_POS) <= SMALL_R * 1.5:
			return "menu"
		if _near_npc() and pos.distance_to(INTERACT_POS) <= DASH_R * 1.25:
			return "interact"
	return ""


func _near_npc() -> bool:
	return town != null and not town.near_npc().is_empty()


func _touch_down(idx: int, pos: Vector2) -> void:
	var b := _hit(pos)
	if b != "":
		_btn_touch[idx] = b
		match b:
			"dash":
				_tap_action("dash")
			"ult":
				_tap_action("ult")
			"pause":
				pause_pressed.emit()
			"detail":
				detail_pressed.emit()
			"menu":
				menu_pressed.emit()
			"interact":
				interact_pressed.emit()
		return
	if _stick_idx < 0 and pos.x < 640.0 and pos.y > 110.0:         # 左半屏任意处按下 = 摇杆原点（浮动摇杆）
		_stick_idx = idx
		_stick_origin = pos
		_stick_pos = pos
		_apply_move(Vector2.ZERO)


func _touch_up(idx: int) -> void:
	_btn_touch.erase(idx)
	if idx == _stick_idx:
		_stick_idx = -1
		_apply_move(Vector2.ZERO)


func _stick_move(pos: Vector2) -> void:
	var d := pos - _stick_origin
	if d.length() > STICK_R:                      # 手指拖出圈外：摇杆原点跟着走，不会「卡」在原地
		_stick_origin = pos - d.normalized() * STICK_R
		d = pos - _stick_origin
	_stick_pos = _stick_origin + d
	_apply_move(d / STICK_R)


func _apply_move(v: Vector2) -> void:
	move_vec = v
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_up", "move_down", v.y)


func _set_axis(neg: String, pos: String, val: float) -> void:
	if val < -0.01:
		Input.action_press(neg, minf(1.0, -val))
		Input.action_release(pos)
	elif val > 0.01:
		Input.action_press(pos, minf(1.0, val))
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _tap_action(action: String) -> void:
	Input.action_press(action)
	get_tree().create_timer(0.09).timeout.connect(func() -> void: Input.action_release(action))


func _release_all() -> void:
	_stick_idx = -1
	_btn_touch.clear()
	_apply_move(Vector2.ZERO)


func _draw_pad() -> void:
	if not is_active():
		return
	var font := _pad.get_theme_default_font()
	if _stick_idx >= 0:                       # 摇杆：外圈 + 内点
		_pad.draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.08))
		_pad.draw_arc(_stick_origin, STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		_pad.draw_circle(_stick_pos, 30.0, Color(1, 1, 1, 0.28))
	else:                                     # 没按时在左下角淡淡提示摇杆位置
		_pad.draw_arc(Vector2(170, 590), STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 3.0)
		_pad.draw_string(font, Vector2(130, 598), "移动", HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color(1, 1, 1, 0.3))
	if mode == "play":
		_round_btn(DASH_POS, DASH_R, "轻功", Color("#3aa6a0"), _btn_pressed("dash"), true)
		var burst_ok := world != null and world.burst_left() > 0 and world.can_burst()
		_round_btn(ULT_POS, ULT_R, "爆发", Color("#c8742a"), _btn_pressed("ult"), burst_ok)
		_round_btn(PAUSE_POS, SMALL_R, "停", Color("#aaaaaa"), _btn_pressed("pause"), true)
		_round_btn(DETAIL_POS, SMALL_R, "详", Color("#aaaaaa"), _btn_pressed("detail"), true)
	elif mode == "town":
		_round_btn(MENU_POS, SMALL_R + 4.0, "菜单", Color("#aaaaaa"), _btn_pressed("menu"), true)
		if _near_npc():
			_round_btn(INTERACT_POS, DASH_R, "交谈", Color("#e6c65a"), _btn_pressed("interact"), true)


func _btn_pressed(name: String) -> bool:
	return _btn_touch.values().has(name)


func _round_btn(c: Vector2, r: float, text: String, col: Color, pressed: bool, enabled: bool) -> void:
	var a := 0.55 if enabled else 0.22
	_pad.draw_circle(c, r, Color(col, (0.42 if pressed else 0.2) * (1.0 if enabled else 0.6)))
	_pad.draw_arc(c, r, 0.0, TAU, 36, Color(col, a + (0.25 if pressed else 0.0)), 3.0)
	var font := _pad.get_theme_default_font()
	var fs := 22 if r > 40.0 else 16
	_pad.draw_string(font, c + Vector2(-r, fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.9 if enabled else 0.4))
