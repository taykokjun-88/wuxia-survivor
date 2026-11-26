class_name TouchControls
extends CanvasLayer
## 手机 / 平板（含 iPad）触控：左半屏「浮动摇杆」（带防误触死区）+ 右下角技能键（轻功冷却/次数 + 真气爆发脉冲）+ 暂停 / 详情；村子里是摇杆 + 「交谈(NPC名)」+ 菜单。
## 只在触屏设备上出现（检测到触摸 / 系统报告有触屏）；一旦收到键盘按键就自动隐藏（笔记本触屏 + 键盘不会重复显示）。
## 所有按钮坐标按当前视口动态锚定，兼容 16:9 手机与 4:3 iPad 屏幕，避开 iOS 边缘手势区。

signal pause_pressed
signal detail_pressed
signal interact_pressed
signal menu_pressed

const STICK_R := 72.0
const STICK_DEADZONE := 0.14    # 摇杆死区：避免拇指微抖意外打断「入定」
const DASH_POS := Vector2(1162, 598)
const DASH_R := 60.0
const ULT_POS := Vector2(1024, 638)
const ULT_R := 48.0
const PAUSE_POS := Vector2(1222, 108)
const DETAIL_POS := Vector2(1222, 182)
const SMALL_R := 30.0           # iPad 友好尺寸（直径 60px），远离屏幕边缘防触发 iOS 返回手势
const MENU_POS := Vector2(1222, 58)
const INTERACT_POS := Vector2(1162, 598)

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
var _pulse_t := 0.0


func _ready() -> void:
	layer = 20
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad)
	_pad.draw.connect(_draw_pad)


func _vs() -> Vector2:
	var s := _pad.get_viewport_rect().size if (_pad != null and _pad.is_inside_tree()) else Vector2(1280, 720)
	return s if s.x > 100.0 and s.y > 100.0 else Vector2(1280, 720)


func _pos(name: String) -> Vector2:
	var vs := _vs()
	match name:
		"dash", "interact": return Vector2(vs.x - 118.0, vs.y - 122.0)
		"ult": return Vector2(vs.x - 256.0, vs.y - 82.0)
		"pause": return Vector2(vs.x - 58.0, 108.0)
		"detail": return Vector2(vs.x - 58.0, 182.0)
		"menu": return Vector2(vs.x - 58.0, 58.0)
		"stick_idle": return Vector2(168.0, vs.y - 130.0)
	return Vector2.ZERO


func is_active() -> bool:
	return mode != "" and not keyboard_seen and (touch_seen or DisplayServer.is_touchscreen_available())


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	_release_all()
	_pad.visible = m != ""


func _process(dt: float) -> void:
	_pad.visible = is_active()
	if _pad.visible:
		_pulse_t += dt
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
			if _touch_down(st.index, st.position) and is_inside_tree():
				get_viewport().set_input_as_handled()
		else:
			if _touch_up(st.index) and is_inside_tree():
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_idx:
			_stick_move(sd.position)
			if is_inside_tree():
				get_viewport().set_input_as_handled()


## 点中了哪个按钮（返回按钮名，没点中返回 ""）
func _hit(pos: Vector2) -> String:
	if mode == "play":
		if pos.distance_to(_pos("dash")) <= DASH_R * 1.25:
			return "dash"
		if pos.distance_to(_pos("ult")) <= ULT_R * 1.25:
			return "ult"
		if pos.distance_to(_pos("pause")) <= SMALL_R * 1.35:
			return "pause"
		if pos.distance_to(_pos("detail")) <= SMALL_R * 1.35:
			return "detail"
	elif mode == "town":
		if pos.distance_to(_pos("menu")) <= SMALL_R * 1.4:
			return "menu"
		if _near_npc() and pos.distance_to(_pos("interact")) <= DASH_R * 1.25:
			return "interact"
	return ""


func _near_npc() -> bool:
	return town != null and not town.near_npc().is_empty()


func _touch_down(idx: int, pos: Vector2) -> bool:
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
		return true
	var vs := _vs()
	if _stick_idx < 0 and pos.x < vs.x * 0.52 and pos.y > 100.0:         # 左半屏任意处按下 = 摇杆原点（浮动摇杆）
		_stick_idx = idx
		_stick_origin = pos
		_stick_pos = pos
		_apply_move(Vector2.ZERO)
		return true
	return false


func _touch_up(idx: int) -> bool:
	var handled := _btn_touch.has(idx) or idx == _stick_idx
	_btn_touch.erase(idx)
	if idx == _stick_idx:
		_stick_idx = -1
		_apply_move(Vector2.ZERO)
	return handled


func _stick_move(pos: Vector2) -> void:
	var d := pos - _stick_origin
	if d.length() > STICK_R:                      # 手指拖出圈外：摇杆原点跟着走，不会「卡」在原地
		_stick_origin = pos - d.normalized() * STICK_R
		d = pos - _stick_origin
	_stick_pos = _stick_origin + d
	var frac := d.length() / STICK_R
	if frac <= STICK_DEADZONE:
		_apply_move(Vector2.ZERO)
	else:
		var scaled := (frac - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
		_apply_move(d.normalized() * clampf(scaled, 0.0, 1.0))


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
	if _stick_idx >= 0:                       # 摇杆：外圈 + 死区提示 + 内点
		_pad.draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.09))
		_pad.draw_arc(_stick_origin, STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.38), 3.0)
		_pad.draw_circle(_stick_pos, 30.0, Color(1, 1, 1, 0.34 if move_vec.length() > 0.01 else 0.22))
		_pad.draw_arc(_stick_pos, 30.0, 0.0, TAU, 28, Color("#f3ead2", 0.55), 2.0)
	else:                                     # 没按时在左下角淡淡提示摇杆位置
		var idle_c := _pos("stick_idle")
		_pad.draw_arc(idle_c, STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.16), 3.0)
		_pad.draw_string(font, idle_c + Vector2(-40, 8), "移动", HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color(1, 1, 1, 0.34))
	if mode == "play":
		# 轻功：显示可用次数 + 冷却进度圈
		var dash_c := _pos("dash")
		var max_ch := int(world.qg.get("charges", 1)) if world != null else 1
		var cur_ch := world.dash_charges if world != null else 1
		var dash_ok := world != null and cur_ch > 0 and not world.dash_sealed() and world.neili >= float(world.qg.get("cost", 0.0))
		var dash_sub := "%d/%d" % [cur_ch, max_ch] if max_ch > 1 else ("就绪" if cur_ch > 0 else "%.1fs" % maxf(0.0, world.dash_recharge))
		_round_btn(dash_c, DASH_R, "轻功", Color("#3aa6a0"), _btn_pressed("dash"), dash_ok, dash_sub)
		if world != null and cur_ch < max_ch:
			var full_cd := float(world.qg.get("cd", 1.0)) * maxf(0.4, 1.0 - world.st("qg_cd_reduce"))
			var prog := clampf(1.0 - world.dash_recharge / maxf(0.1, full_cd), 0.0, 1.0)
			_pad.draw_arc(dash_c, DASH_R + 5.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color("#7ef0e8", 0.85), 3.5)
		# 真气爆发：就绪时金色脉冲光圈 + 剩余次数 + 气海境界提示
		var ult_c := _pos("ult")
		var burst_ok := world != null and world.burst_left() > 0 and world.can_burst()
		var ult_sub := "%d/%d" % [world.burst_left(), world.burst_max()] if world != null else ""
		if burst_ok:
			var pulse := 0.5 + 0.5 * sin(_pulse_t * 5.0)
			_pad.draw_arc(ult_c, ULT_R + 4.0 + pulse * 5.0, 0.0, TAU, 36, Color("#ffd466", 0.35 + 0.4 * pulse), 3.0)
		_round_btn(ult_c, ULT_R, "爆发", Color("#d47a2a"), _btn_pressed("ult"), burst_ok, ult_sub)
		if world != null:
			var r_lbl := "入定" if world.meditating() else ("盈境" if world.realm() == GameWorld.Realm.YING else ("虚境" if world.realm() == GameWorld.Realm.XU else "平境"))
			var r_col := Color("#7ef0e8") if world.meditating() else (Color("#ffd466") if world.realm() == GameWorld.Realm.YING else (Color("#ff6a5a") if world.realm() == GameWorld.Realm.XU else Color("#cfc6ae")))
			var rp := Vector2(ult_c.x - 28.0, ult_c.y - ULT_R - 24.0)
			_pad.draw_rect(Rect2(rp, Vector2(56.0, 18.0)), Color(0.06, 0.06, 0.08, 0.78))
			_pad.draw_rect(Rect2(rp, Vector2(56.0, 18.0)), Color(r_col, 0.75), false, 1.5)
			_pad.draw_string(font, rp + Vector2(0, 14.0), r_lbl, HORIZONTAL_ALIGNMENT_CENTER, 56.0, 12, r_col)
		_round_btn(_pos("pause"), SMALL_R, "停", Color("#cccccc"), _btn_pressed("pause"), true)
		_round_btn(_pos("detail"), SMALL_R, "详", Color("#cccccc"), _btn_pressed("detail"), true)
	elif mode == "town":
		_round_btn(_pos("menu"), SMALL_R + 2.0, "菜单", Color("#cccccc"), _btn_pressed("menu"), true)
		if _near_npc():
			var npc_name := str(town.near_npc().get("name", ""))
			_round_btn(_pos("interact"), DASH_R, "交谈", Color("#e6c65a"), _btn_pressed("interact"), true, npc_name)


func _btn_pressed(name: String) -> bool:
	return _btn_touch.values().has(name)


func _round_btn(c: Vector2, r: float, text: String, col: Color, pressed: bool, enabled: bool, sub: String = "") -> void:
	var a := 0.65 if enabled else 0.25
	_pad.draw_circle(c, r, Color(0.06, 0.06, 0.08, 0.45 if enabled else 0.28))
	_pad.draw_circle(c, r, Color(col, (0.45 if pressed else 0.22) * (1.0 if enabled else 0.5)))
	_pad.draw_arc(c, r, 0.0, TAU, 36, Color(col, a + (0.25 if pressed else 0.0)), 3.0)
	var font := _pad.get_theme_default_font()
	var fs := 22 if r > 40.0 else 17
	var ty := c.y + (fs * 0.1 if sub != "" else fs * 0.36)
	_pad.draw_string(font, Vector2(c.x - r, ty), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.95 if enabled else 0.45))
	if sub != "":
		_pad.draw_string(font, Vector2(c.x - r, ty + 20.0), sub, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, Color("#f7eed8", 0.9 if enabled else 0.45))
