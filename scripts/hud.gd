class_name GameHud
extends CanvasLayer
## HUD：状态条、技能槽、计时、Boss 血条；以及开局选择/升级选择/结算浮层。全部由代码构建。

signal choice_selected(index: int)
signal loadout_confirmed(starter_id: String, qinggong_id: String)
signal character_created(school_id: String)
signal recreate_requested
signal auth_submitted(mode: String, nick: String, pin: String, code: String)
signal board_open_requested
signal board_kind_requested(kind: String)
signal feedback_open_requested
signal feedback_submitted(type: String, comment: String)
signal account_requested
signal modal_closed
signal loadout_cancelled
signal dialog_option(index: int)
signal meta_open_requested
signal meta_saved(alloc: Dictionary)
signal talents_open_requested
signal talents_saved(talents: Dictionary)
signal gear_open_requested
signal gear_saved(equip: Dictionary, discard: Array)

var world: GameWorld
var canvas: Control
var overlay: Control
var overlay_title: Label
var overlay_body: Label
var levelup_panel: Control
var choice_title: Label
var choice_buttons: Array[Button] = []
var loadout_panel: Control
var create_panel: Control
var create_portrait: TextureRect
var create_preview: SpritePreview
var create_desc: Label
var sel_school := "fist"
var auth_panel: Control
var auth_mode := "login"
var auth_nick: LineEdit
var auth_pin: LineEdit
var auth_code: LineEdit
var auth_status: Label
var auth_submit_btn: Button
var auth_busy := false
var board_panel: Control
var board_kind := "score"
var board_group_only := false
var board_grid: GridContainer
var board_status: Label
var feedback_panel: Control
var meta_panel: Control
var loadout_map := "black_wind"      # 本次要出发的地图
var dialog_panel: Control
var dialog_count := 0
var guide_panel: Control
var guide_cat := "play"
var guide_index := 0
var town_layer: Control
var hud_expanded := false          # 局内左侧信息栏：收起（只显示图标）/ 展开（图标 + 名称 + 等级）
var meta_work: Dictionary = {}
var meta_status: Label
var talents_panel: Control
var talents_work: Dictionary = {}
var talents_status: Label
var talents_map: TalentMap
var talents_info_points: Label
var talents_info_branches: VBoxContainer
var talents_info_node: Label
var gear_panel: Control
var gear_equip: Dictionary = {}
var gear_discard: Array = []
var gear_drop_mode := false
var gear_status: Label
var feedback_type: OptionButton
var feedback_text: TextEdit
var feedback_status: Label
var end_base := ""
const FEEDBACK_TYPES := ["bug", "balance", "idea", "other"]
var school := "fist"          # 当前角色的流派
var sel_starter := "chain_fist"
var sel_qg := "tashue"
var diff := {"count": 100, "hp": 100, "speed": 100}     # 难度（百分比，100 ~ 300，步长 10）


func setup(w: GameWorld) -> void:
	world = w
	var ui: Variant = Save.data.get("ui", {})
	hud_expanded = ui is Dictionary and bool((ui as Dictionary).get("hud_expanded", false))
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_hud)
	add_child(canvas)
	_build_overlay()
	_build_levelup()


func _process(_dt: float) -> void:
	if canvas:
		canvas.queue_redraw()


# ---------------------------------------------------------------------
# 浮层
# ---------------------------------------------------------------------

func _dim() -> ColorRect:
	var dim := ColorRect.new()
	# 局内（能看到游戏画面）只压暗一点；村子 / 开局界面里背后的画面很杂，压深一些
	var a := 0.62 if (world != null and world.visible) else 0.92
	dim.color = Color(0.05, 0.05, 0.08, a)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim


func _label(text: String, size: int, color: Color = Color("#f3ead2")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	overlay.add_child(_dim())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	overlay_title = _label("", 56)
	box.add_child(overlay_title)
	overlay_body = _label("", 22)
	box.add_child(overlay_body)


func _build_levelup() -> void:
	levelup_panel = Control.new()
	levelup_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.visible = false
	add_child(levelup_panel)
	levelup_panel.add_child(_dim())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	choice_title = _label("", 28)
	box.add_child(choice_title)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(700, 88)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): choice_selected.emit(i))
		box.add_child(b)
		choice_buttons.append(b)


func _panel_box() -> Array:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	add_child(panel)
	panel.add_child(_dim())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	return [panel, box]


## 创建角色（只在第一次进入游戏时出现）：选择武学流派
func _school_portrait(school_id: String) -> Texture2D:
	var path := str(Data.schools[school_id].get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null


func _on_school_selected(id: String) -> void:
	sel_school = id
	if create_portrait:
		create_portrait.texture = _school_portrait(id)
	if create_preview:
		create_preview.setup(id)
	if create_desc:
		create_desc.text = str(Data.schools[id]["desc"])


## 创建角色（只在第一次进入游戏时出现）：立绘 + 选择流派 + 像素形象预览
func _build_create() -> void:
	if create_panel:
		create_panel.queue_free()
	var pb := _panel_box()
	create_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("创建角色", 40))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)

	# 左：立绘
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#10141a")
	sb.border_color = Color("#c9a227")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	create_portrait = TextureRect.new()
	create_portrait.custom_minimum_size = Vector2(390, 520)
	create_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	create_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	create_portrait.texture = _school_portrait(sel_school)
	frame.add_child(create_portrait)
	row.add_child(frame)

	# 右：流派 + 像素形象 + 创建
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(560, 0)
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var hint := _label("选择你的武学流派。流派决定可学的招式，创建后不可在局内更改。", 16, Color("#cfc6ae"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	right.add_child(hint)
	var srow := _center_row(10)
	right.add_child(srow)
	var group := ButtonGroup.new()
	for id in Data.schools:
		var sd: Dictionary = Data.schools[id]
		var enabled := bool(sd["enabled"])
		var b := Button.new()
		b.text = "%s\n%s" % [sd["name"], "可选" if enabled else "敬请期待"]
		b.custom_minimum_size = Vector2(128, 70)
		b.disabled = not enabled
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == sel_school
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_school_selected.bind(id))
		srow.add_child(b)
	create_desc = _label(str(Data.schools[sel_school]["desc"]), 18, Color("#f3ead2"))
	right.add_child(create_desc)
	create_preview = SpritePreview.new()
	create_preview.custom_minimum_size = Vector2(560, 330)
	create_preview.setup(sel_school)
	right.add_child(create_preview)
	var ok := _button("创建角色  [Enter]", Vector2(260, 48), 22)
	ok.pressed.connect(confirm_create)
	var brow := _center_row()
	brow.add_child(ok)
	right.add_child(brow)


## 每局开局：起手招式 + 轻功（流派已在创建角色时确定）
func _build_loadout() -> void:
	if loadout_panel:
		loadout_panel.queue_free()
	var pb := _panel_box()
	loadout_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_child(_label("出发：%s" % str(Data.maps[loadout_map]["name"]), 52))
	box.add_child(_label("角色流派：%s　　WASD 移动（自动攻击）　空格 轻功　E 真气爆发" % Data.schools[school]["name"], 16, Color("#cfc6ae")))
	box.add_child(_label("内力盈（≥%d%%）：伤害 +%d%%，招式自动「催动」（消耗内力）　·　站定不动 %.1f 秒入定：回气更快、减伤" % [
		int(round(Data.T("ying_at") * 100.0)), int(round((Data.T("ying_dmg") - 1.0) * 100.0)), Data.T("meditate_after")],
		15, Color("#9ad0a0")))

	# 起手招式（3 选 1）。天赋加点（刚/柔/灵）是独立的局外系统，不在这里选。
	box.add_child(_label("起手招式（3 选 1）", 20, Color("#c9a227")))
	var starter_row := HBoxContainer.new()
	starter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	starter_row.add_theme_constant_override("separation", 10)
	box.add_child(starter_row)
	var sgroup := ButtonGroup.new()
	for id in Data.schools[school]["starters"]:
		var sd: Dictionary = Data.skills[id]
		var b := Button.new()
		b.text = "%s　【%s】\n%s" % [sd["name"], Data.tags_text(id), sd["desc"]]
		b.custom_minimum_size = Vector2(340, 72)
		b.toggle_mode = true
		b.button_group = sgroup
		b.button_pressed = id == sel_starter
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): sel_starter = id)
		starter_row.add_child(b)

	# 轻功
	box.add_child(_label("轻功（6 选 1）", 20, Color("#c9a227")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var qgroup := ButtonGroup.new()
	for id in Data.qinggong:
		var qd: Dictionary = Data.qinggong[id]
		var b := Button.new()
		b.text = "%s\n%s" % [qd["name"], qd["desc"]]
		b.custom_minimum_size = Vector2(330, 64)
		b.toggle_mode = true
		b.button_group = qgroup
		b.button_pressed = id == sel_qg
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): sel_qg = id)
		grid.add_child(b)

	# 难度调节：三个滑条（怪物数量 / 血量 / 移动速度），100% ~ 300%
	_load_difficulty()
	box.add_child(_label("难度调节（100% = 标准）", 20, Color("#c9a227")))
	var drow := _center_row(26)
	var sum_lbl := _label("", 16, Color("#cfc6ae"))
	var upd := func():
		var avg := (float(diff["count"]) + float(diff["hp"]) + float(diff["speed"])) / 300.0
		var rew := ""
		if avg > 1.0:
			rew = "　→　局内经验 +%d%%　修为 +%d%%　装备更多更好" % [int(round((avg - 1.0) * float(Data.difficulty["exp_in_run"]) * 100.0)), int(round((avg - 1.0) * float(Data.difficulty["exp_meta"]) * 100.0))]
		sum_lbl.text = "综合难度 ×%.1f%s" % [avg, rew]
	for spec in [["count", "怪物数量"], ["hp", "怪物血量"], ["speed", "移动速度"]]:
		var key: String = spec[0]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var val := _label("%s　%d%%" % [spec[1], int(diff[key])], 17, Color("#f3ead2"))
		col.add_child(val)
		var sl := HSlider.new()
		sl.min_value = 100
		sl.max_value = 300
		sl.step = 10
		sl.value = int(diff[key])
		sl.custom_minimum_size = Vector2(250, 22)
		sl.focus_mode = Control.FOCUS_NONE
		var track := StyleBoxFlat.new()
		track.bg_color = Color("#4a4438")
		track.set_corner_radius_all(3)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("#c9a227")
		fill.set_corner_radius_all(3)
		sl.add_theme_stylebox_override("slider", track)
		sl.add_theme_stylebox_override("grabber_area", fill)
		sl.add_theme_stylebox_override("grabber_area_highlight", fill)
		sl.value_changed.connect(func(v: float):
			diff[key] = int(v)
			val.text = "%s　%d%%" % [spec[1], int(v)]
			upd.call())
		col.add_child(sl)
		drow.add_child(col)
	box.add_child(drow)
	upd.call()
	box.add_child(sum_lbl)
	var start := Button.new()
	start.text = "开始闯荡  [Enter]"
	start.custom_minimum_size = Vector2(260, 48)
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(confirm_loadout)
	var back := _button("返回村子  [Esc]", Vector2(190, 48), 18)
	back.pressed.connect(func(): loadout_cancelled.emit())
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 16)
	srow.add_child(start)
	srow.add_child(back)
	box.add_child(srow)


func confirm_create() -> void:
	character_created.emit(sel_school)


## 难度百分比 → 倍率
func difficulty_factors() -> Dictionary:
	return {"count": float(diff["count"]) / 100.0, "hp": float(diff["hp"]) / 100.0, "speed": float(diff["speed"]) / 100.0}


func _load_difficulty() -> void:
	var ui: Variant = Save.data.get("ui", {})
	if ui is Dictionary and (ui as Dictionary).get("difficulty") is Dictionary:
		var d: Dictionary = (ui as Dictionary)["difficulty"]
		for k in ["count", "hp", "speed"]:
			diff[k] = clampi(int(round(float(d.get(k, 100)) / 10.0)) * 10, 100, 300)


func _save_difficulty() -> void:
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	(ui as Dictionary)["difficulty"] = diff.duplicate()
	Save.data["ui"] = ui
	Save.save_data()


func confirm_loadout() -> void:
	_save_difficulty()
	loadout_confirmed.emit(sel_starter, sel_qg)


func show_create() -> void:
	_build_create()
	create_panel.visible = true
	overlay.visible = false


func hide_create() -> void:
	if create_panel:
		create_panel.visible = false


func show_loadout(school_id: String, map_id: String = "black_wind") -> void:
	loadout_map = map_id
	school = school_id
	var starters: Array = Data.schools[school]["starters"]
	if not starters.has(sel_starter):
		sel_starter = str(starters[0])
	_build_loadout()
	loadout_panel.visible = true
	overlay.visible = false


func hide_loadout() -> void:
	if loadout_panel:
		loadout_panel.visible = false


# ---------------------------------------------------------------------
# 账号 / 排行榜 / 反馈（需要在线服务；api_url 为空时这些界面不会出现）
# ---------------------------------------------------------------------

func _button(text: String, size: Vector2, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _field(placeholder: String, secret: bool, max_len: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.secret = secret
	le.secret_character = "*"   # 默认的 • 不在自带字库里，会显示成方块
	le.max_length = max_len
	le.custom_minimum_size = Vector2(380, 46)
	le.add_theme_font_size_override("font_size", 20)
	le.text_submitted.connect(func(_t: String): _submit_auth())
	return le


func _center_row(sep: int = 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", sep)
	return row


func show_message(text: String) -> void:
	overlay_title.text = "武侠幸存者"
	overlay_body.text = text
	overlay.visible = true


func _build_auth(prefill: String) -> void:
	if auth_panel:
		auth_panel.queue_free()
	var pb := _panel_box()
	auth_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_child(_label("武侠幸存者", 52))
	box.add_child(_label("请登录。还没有账号？点「注册」，需要管理员给你的邀请码", 18, Color("#cfc6ae")))
	var mode_row := _center_row(10)
	box.add_child(mode_row)
	var group := ButtonGroup.new()
	for m in [["login", "登录"], ["register", "注册"]]:
		var b := _button(m[1], Vector2(150, 44))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = auth_mode == m[0]
		b.pressed.connect(func(): auth_mode = m[0]; _refresh_auth())
		mode_row.add_child(b)
	auth_nick = _field("昵称（2–12 个字）", false, 12)
	auth_nick.text = prefill
	auth_pin = _field("PIN（4–8 位数字）", true, 8)
	auth_code = _field("邀请码（注册必填，找管理员要）", false, 12)
	for f in [auth_nick, auth_pin, auth_code]:
		var r := _center_row()
		r.add_child(f)
		box.add_child(r)
	auth_status = _label("", 16, Color("#f08070"))
	auth_status.custom_minimum_size = Vector2(0, 24)
	box.add_child(auth_status)
	var btns := _center_row(16)
	auth_submit_btn = _button("登录", Vector2(260, 50), 22)
	auth_submit_btn.pressed.connect(_submit_auth)
	btns.add_child(auth_submit_btn)
	box.add_child(btns)
	_refresh_auth()


func _refresh_auth() -> void:
	auth_code.get_parent().visible = auth_mode == "register"
	auth_submit_btn.text = "注册并进入" if auth_mode == "register" else "登录"
	auth_status.text = ""


func _submit_auth() -> void:
	if auth_busy:
		return
	var n := auth_nick.text.strip_edges()
	var pin := auth_pin.text
	if n.length() < 2:
		return set_auth_status("昵称至少 2 个字", true)
	if pin.length() < 4 or not pin.is_valid_int():
		return set_auth_status("PIN 要是 4–8 位数字", true)
	if auth_mode == "register" and auth_code.text.strip_edges() == "":
		return set_auth_status("请填写邀请码", true)
	auth_submitted.emit(auth_mode, n, pin, auth_code.text.strip_edges())


func set_auth_status(msg: String, is_error: bool) -> void:
	if auth_status:
		auth_status.text = msg
		auth_status.add_theme_color_override("font_color", Color("#f08070") if is_error else Color("#cfc6ae"))


func set_auth_busy(busy: bool) -> void:
	auth_busy = busy
	if auth_submit_btn:
		auth_submit_btn.disabled = busy


func show_auth(prefill: String = "") -> void:
	_build_auth(prefill)
	auth_panel.visible = true
	overlay.visible = false
	(auth_pin if prefill != "" else auth_nick).call_deferred("grab_focus")


func hide_auth() -> void:
	if auth_panel:
		auth_panel.visible = false


func _cell(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	return l


func _commas(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	for i in t.length():
		if i > 0 and (t.length() - i) % 3 == 0:
			out += ","
		out += t[i]
	return ("-" if n < 0 else "") + out


func _board_value(kind: String, v: float) -> String:
	match kind:
		"speed": return "%d:%02d" % [int(v / 60.0), int(v) % 60]
		"level": return "Lv%d" % int(v)
	return _commas(int(v))


func _build_board() -> void:
	if board_panel:
		board_panel.queue_free()
	var pb := _panel_box()
	board_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("排行榜", 44))
	var tabs := _center_row(10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	if Net.group_name != "":
		var scope := CheckButton.new()
		scope.text = "仅看本群（%s）" % Net.group_name
		scope.button_pressed = board_group_only
		scope.focus_mode = Control.FOCUS_NONE
		scope.add_theme_font_size_override("font_size", 16)
		scope.toggled.connect(func(on: bool): board_group_only = on; board_kind_requested.emit(board_kind))
		var scope_row := _center_row()
		scope.custom_minimum_size = Vector2(320, 0)
		scope_row.add_child(scope)
		box.add_child(scope_row)
	for k in [["score", "总分榜"], ["speed", "最快通关"], ["level", "最高等级"]]:
		var b := _button(k[1], Vector2(150, 42))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = board_kind == k[0]
		b.pressed.connect(func(): board_kind = k[0]; board_kind_requested.emit(k[0]))
		tabs.add_child(b)
	board_status = _label("", 16, Color("#cfc6ae"))
	box.add_child(board_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 390)
	box.add_child(scroll)
	board_grid = GridContainer.new()
	board_grid.columns = 4
	board_grid.add_theme_constant_override("h_separation", 40)
	board_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(board_grid)
	var btns := _center_row(16)
	var refresh := _button("刷新", Vector2(130, 42), 18)
	refresh.pressed.connect(func(): board_kind_requested.emit(board_kind))
	var close := _button("关闭  [Esc]", Vector2(150, 42), 18)
	close.pressed.connect(func(): modal_closed.emit())
	btns.add_child(refresh)
	btns.add_child(close)
	box.add_child(btns)


func show_board() -> void:
	_build_board()
	board_status.text = "加载中…"
	board_panel.visible = true


func hide_board() -> void:
	if board_panel:
		board_panel.visible = false


func update_board(kind: String, res: Dictionary) -> void:
	if board_grid == null or kind != board_kind:
		return
	for c in board_grid.get_children():
		c.queue_free()
	if not bool(res.get("ok", false)):
		board_status.text = str(res.get("msg", "加载失败"))
		return
	var titles := {"score": "得分", "speed": "用时", "level": "等级"}
	for h in ["名次", "昵称", titles[kind], "流派"]:
		board_grid.add_child(_cell(h, Color("#c9a227")))
	for r in res["rows"]:
		var mine := Net.nick != "" and str(r["nick"]).to_lower() == Net.nick.to_lower()
		var col := Color("#f0c050") if mine else Color("#f3ead2")
		var sch := str(r.get("school", ""))
		board_grid.add_child(_cell("%d" % int(r["rank"]), col))
		board_grid.add_child(_cell(str(r["nick"]), col))
		board_grid.add_child(_cell(_board_value(kind, float(r["value"])), col))
		board_grid.add_child(_cell(str(Data.schools[sch]["name"]) if Data.schools.has(sch) else "", col))
	var me: Variant = res.get("me")
	if (res["rows"] as Array).is_empty():
		board_status.text = "还没有人上榜，来当第一个吧"
	elif me is Dictionary:
		board_status.text = "我的名次：第 %d 名（%s）　共 %d 人上榜" % [int(me["rank"]), _board_value(kind, float(me["value"])), int(res["total"])]
	elif Net.logged_in():
		board_status.text = "你还没有这个榜的成绩　共 %d 人上榜" % int(res["total"])
	else:
		board_status.text = "游客不在榜上，登录后成绩才会上榜　共 %d 人上榜" % int(res["total"])


func _build_feedback() -> void:
	if feedback_panel:
		feedback_panel.queue_free()
	var pb := _panel_box()
	feedback_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_child(_label("给我们反馈", 44))
	box.add_child(_label("Bug、太难或太简单、想要的功能……都可以写", 18, Color("#cfc6ae")))
	var row := _center_row()
	feedback_type = OptionButton.new()
	feedback_type.custom_minimum_size = Vector2(300, 44)
	feedback_type.add_theme_font_size_override("font_size", 20)
	for t in ["Bug / 卡住了", "难度 / 平衡", "建议 / 想法", "其他"]:
		feedback_type.add_item(t)
	row.add_child(feedback_type)
	box.add_child(row)
	feedback_text = TextEdit.new()
	feedback_text.custom_minimum_size = Vector2(600, 150)
	feedback_text.placeholder_text = "写在这里（最多 500 字）"
	feedback_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	feedback_text.add_theme_font_size_override("font_size", 20)
	box.add_child(feedback_text)
	feedback_status = _label("", 16, Color("#cfc6ae"))
	feedback_status.custom_minimum_size = Vector2(0, 24)
	box.add_child(feedback_status)
	var btns := _center_row(16)
	var send := _button("发送", Vector2(160, 46), 22)
	send.pressed.connect(func():
		var t := feedback_text.text.strip_edges()
		if t.length() < 2:
			set_feedback_status("请写点内容", true)
		else:
			feedback_submitted.emit(FEEDBACK_TYPES[feedback_type.selected], t.substr(0, 500)))
	var cancel := _button("取消  [Esc]", Vector2(160, 46), 18)
	cancel.pressed.connect(func(): modal_closed.emit())
	btns.add_child(send)
	btns.add_child(cancel)
	box.add_child(btns)


func show_feedback() -> void:
	_build_feedback()
	feedback_panel.visible = true
	feedback_text.call_deferred("grab_focus")


func hide_feedback() -> void:
	if feedback_panel:
		feedback_panel.visible = false


func set_feedback_status(msg: String, is_error: bool) -> void:
	if feedback_status:
		feedback_status.text = msg
		feedback_status.add_theme_color_override("font_color", Color("#f08070") if is_error else Color("#9ad0a0"))


# ---------------------------------------------------------------------
# 角色成长：修为 / 等级 / 五种属性点分配
# ---------------------------------------------------------------------

func show_meta() -> void:
	meta_work = Save.meta_alloc()
	_build_meta()
	meta_panel.visible = true


func hide_meta() -> void:
	if meta_panel:
		meta_panel.visible = false


func set_meta_status(msg: String, is_error: bool) -> void:
	if meta_status:
		meta_status.text = msg
		meta_status.add_theme_color_override("font_color", Color("#f08070") if is_error else Color("#9ad0a0"))


func _meta_add(attr_id: String, delta: int, free_pts: int) -> void:
	var cur := int(meta_work[attr_id])
	var d := clampi(delta, -cur, mini(free_pts, Meta.ATTR_CAP - cur)) if delta > 0 else maxi(delta, -cur)
	meta_work[attr_id] = cur + d
	_build_meta()
	meta_panel.visible = true


func _build_meta() -> void:
	if meta_panel:
		meta_panel.queue_free()
	var pb := _panel_box()
	meta_panel = pb[0]
	var box: VBoxContainer = pb[1]
	var exp := Save.meta_exp() if not Net.logged_in() else Net.exp
	var mp := Meta.progress(exp)
	var level: int = mp["level"]
	var free_pts := Meta.points_total(level) - Meta.points_used(meta_work)
	box.add_child(_label("角色成长", 44))
	var head := "局外等级 Lv %d%s" % [level, "（满级）" if level >= Meta.MAX_LEVEL else ""]
	box.add_child(_label(head, 24, Color("#c9a227")))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(560, 22)
	bar.max_value = maxf(1.0, float(mp["need"]))
	bar.value = float(mp["into"]) if level < Meta.MAX_LEVEL else bar.max_value
	bar.show_percentage = false
	var brow := _center_row()
	brow.add_child(bar)
	box.add_child(brow)
	box.add_child(_label(("修为 %s / %s" % [_commas(mp["into"]), _commas(mp["need"])]) if level < Meta.MAX_LEVEL else "修为已满", 16, Color("#cfc6ae")))
	box.add_child(_label("未分配属性点：%d　　天赋点：%d（天赋树开发中）" % [free_pts, level], 20,
		Color("#9ad0a0") if free_pts > 0 else Color("#f3ead2")))
	for a in Meta.ATTRS:
		var id: String = a["id"]
		var pts := int(meta_work[id])
		var row := _center_row(8)
		var nm := _label(str(a["name"]), 22)
		nm.custom_minimum_size = Vector2(64, 0)
		row.add_child(nm)
		var pbar := ProgressBar.new()
		pbar.custom_minimum_size = Vector2(150, 18)
		pbar.max_value = Meta.ATTR_CAP
		pbar.value = pts
		pbar.show_percentage = false
		var pc := CenterContainer.new()
		pc.add_child(pbar)
		row.add_child(pc)
		var val := _label(str(pts), 22, Color("#c9a227"))
		val.custom_minimum_size = Vector2(40, 0)
		row.add_child(val)
		for spec in [["−", -1], ["+", 1], ["+5", 5]]:
			var d: int = spec[1]
			var bt := _button(str(spec[0]), Vector2(48, 34), 18)
			bt.disabled = (d < 0 and pts <= 0) or (d > 0 and (free_pts <= 0 or pts >= Meta.ATTR_CAP))
			bt.pressed.connect(_meta_add.bind(id, d, free_pts))
			row.add_child(bt)
		var fx := _label(Meta.effect_text(id, pts), 15, Color("#cfc6ae"))
		fx.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		fx.custom_minimum_size = Vector2(330, 0)
		row.add_child(fx)
		box.add_child(row)
	box.add_child(_label("越往后每点效果越小：前 30 点满效，31~60 点 60%，61~99 点 30%。随时可以免费重置。", 15, Color("#8d8670")))
	meta_status = _label("", 16, Color("#cfc6ae"))
	meta_status.custom_minimum_size = Vector2(0, 24)
	box.add_child(meta_status)
	var btns := _center_row(16)
	var reset := _button("全部重置", Vector2(150, 46), 18)
	reset.pressed.connect(func():
		meta_work = Meta.clean_alloc({})
		_build_meta()
		meta_panel.visible = true)
	var tal := _button("天赋树（%d 点可用）" % maxi(0, Talents.total_points(level) - Talents.spent(Save.meta_talents())), Vector2(200, 46), 18)
	tal.pressed.connect(func(): talents_open_requested.emit())
	var save := _button("保存", Vector2(160, 46), 22)
	save.pressed.connect(func(): meta_saved.emit(meta_work.duplicate()))
	var cancel := _button("返回  [Esc]", Vector2(160, 46), 18)
	cancel.pressed.connect(func(): modal_closed.emit())
	btns.add_child(reset)
	btns.add_child(tal)
	btns.add_child(save)
	btns.add_child(cancel)
	box.add_child(btns)


# ---------------------------------------------------------------------
# 天赋树
# ---------------------------------------------------------------------

func show_talents() -> void:
	talents_work = Save.meta_talents()
	_build_talents()
	talents_panel.visible = true


func hide_talents() -> void:
	if talents_panel:
		talents_panel.visible = false


func set_talents_status(msg: String, is_error: bool) -> void:
	if talents_status:
		talents_status.text = msg
		talents_status.add_theme_color_override("font_color", Color("#f08070") if is_error else Color("#9ad0a0"))


func _build_talents() -> void:
	if talents_panel:
		talents_panel.queue_free()
	var pb := _panel_box()
	talents_panel = pb[0]
	var box: VBoxContainer = pb[1]
	var level := Meta.level_of(Save.meta_exp())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	box.add_child(hb)
	var tmap := TalentMap.new()
	tmap.work = talents_work
	tmap.level = level
	tmap.custom_minimum_size = Vector2(430, 641)
	hb.add_child(tmap)
	talents_map = tmap
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	var title := _label("经脉图", 40)
	right.add_child(title)
	talents_info_points = _label("", 18)
	right.add_child(talents_info_points)
	talents_info_branches = VBoxContainer.new()
	talents_info_branches.add_theme_constant_override("separation", 4)
	right.add_child(talents_info_branches)
	talents_info_node = Label.new()
	talents_info_node.custom_minimum_size = Vector2(470, 150)
	talents_info_node.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	talents_info_node.add_theme_font_size_override("font_size", 17)
	talents_info_node.add_theme_color_override("font_color", Color("#f3ead2"))
	right.add_child(talents_info_node)
	var hint := _label("左键加点，右键减点。穴位由丹田向外，一层一层打通：每层需要本系更低层投入 ≥ 层号 × %d 点。三系共 35 点一系，总点数只有等级那么多，要取舍。" % Talents.gate(), 14, Color("#8d8670"))
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint.custom_minimum_size = Vector2(470, 0)
	right.add_child(hint)
	talents_status = _label("", 16, Color("#cfc6ae"))
	talents_status.custom_minimum_size = Vector2(0, 22)
	right.add_child(talents_status)
	var btns := _center_row(12)
	var reset := _button("全部重置", Vector2(140, 44), 18)
	reset.pressed.connect(func():
		talents_map.work.clear()
		talents_map.changed.emit()
		talents_map.queue_redraw())
	var save := _button("保存", Vector2(150, 44), 22)
	save.pressed.connect(func(): talents_saved.emit(talents_map.work.duplicate()))
	var cancel := _button("返回  [Esc]", Vector2(150, 44), 18)
	cancel.pressed.connect(func(): modal_closed.emit())
	btns.add_child(reset)
	btns.add_child(save)
	btns.add_child(cancel)
	right.add_child(btns)
	tmap.changed.connect(_talents_refresh)
	tmap.hovered.connect(func(_id: String): _talents_refresh())
	_talents_refresh()


func _talents_refresh() -> void:
	if talents_map == null:
		return
	var work := talents_map.work
	var level := talents_map.level
	var free_pts := Talents.total_points(level) - Talents.spent(work)
	talents_info_points.text = "可用天赋点 %d　（局外等级 %d，共 %d 点）" % [free_pts, level, Talents.total_points(level)]
	talents_info_points.add_theme_color_override("font_color", Color("#9ad0a0") if free_pts > 0 else Color("#cfc6ae"))
	for c in talents_info_branches.get_children():
		c.queue_free()
	for b in Talents.branches():
		var bd: Dictionary = Data.talents["branches"][b]
		var names: Array = []
		for mer in talents_map.meridians:
			if mer["branch"] == b:
				var sub := 0
				for id in mer["ids"]:
					sub += int(work.get(id, 0))
				names.append("%s %d" % [mer["name"], sub])
		var l := _label("%s　%d / 35　　%s　　%s" % [bd["name"], Talents.branch_spent(work, b), "　".join(names), bd["desc"]], 15,
			Color(str(Data.talents["map"]["colors"][b])))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		talents_info_branches.add_child(l)
	var id: String = talents_map.hover_id
	if id == "":
		talents_info_node.text = "把鼠标移到穴位上查看。\n\n◎ 丹田是起点，六条经脉由此向外。\n暗：还没打通　亮环：可以加点　金：已满。"
		return
	var n: Dictionary = Talents.nodes()[id]
	var rank := int(work.get(id, 0))
	var mer_name := ""
	for mer in talents_map.meridians:
		if (mer["ids"] as Array).has(id):
			mer_name = str(mer["name"])
	var lower := 0
	for id2 in work:
		var n2: Dictionary = Talents.nodes()[id2]
		if n2["branch"] == n["branch"] and int(n2["row"]) < int(n["row"]):
			lower += int(work[id2])
	var need := int(n["row"]) * Talents.gate()
	var state := "已满" if rank >= int(n["max"]) else ("可以加点" if Talents.can_add(work, id, talents_map.level) else
		("需要本系更低层投入 %d 点（现有 %d）" % [need, lower] if lower < need else "没有可用的天赋点"))
	talents_info_node.text = "%s　%d / %d\n%s · 第 %d 个穴位\n%s\n（%s）" % [n["name"], rank, n["max"], mer_name, int(n["row"]) + 1, n["desc"], state]


# ---------------------------------------------------------------------
# 装备
# ---------------------------------------------------------------------

func show_gear() -> void:
	gear_equip = Save.equip()
	gear_discard = []
	gear_drop_mode = false
	_build_gear()
	gear_panel.visible = true


func hide_gear() -> void:
	if gear_panel:
		gear_panel.visible = false


func set_gear_status(msg: String, is_error: bool) -> void:
	if gear_status:
		gear_status.text = msg
		gear_status.add_theme_color_override("font_color", Color("#f08070") if is_error else Color("#9ad0a0"))


func _gear_refresh() -> void:
	_build_gear()
	gear_panel.visible = true


func _gear_item_click(code: String) -> void:
	var slot := str(Gear.parse(code)["slot"])
	if gear_drop_mode:
		gear_discard.append(code)
		if gear_equip.get(slot, "") == code:
			gear_equip.erase(slot)
	else:
		gear_equip[slot] = code
	_gear_refresh()


func _gear_button(code: String, w_min: int, h_min: int, compact: bool = false) -> Button:
	var it := Gear.make(code, Save.school())
	var bt := Button.new()
	bt.custom_minimum_size = Vector2(w_min, h_min)
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_font_size_override("font_size", 13)
	var full := "【%s】%s（%s）\n%s" % [it["rarity_name"], it["name"], it["slot_name"], Gear.describe(it)]
	var second := Gear.describe(it)
	if compact:
		var aff: Array = []
		for a in it["affixes"]:
			aff.append("★" + str(a["text"]))
		second = "　".join(aff) if not aff.is_empty() else Gear.describe(it)
	bt.text = "【%s】%s\n%s" % [it["rarity_name"], it["name"], second] if compact else full
	bt.tooltip_text = full
	bt.clip_text = true
	var col := Color(str(it["color"]))
	bt.add_theme_color_override("font_color", col)
	bt.add_theme_color_override("font_hover_color", col)
	return bt


func _build_gear() -> void:
	if gear_panel:
		gear_panel.queue_free()
	var pb := _panel_box()
	gear_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("装备", 36))
	box.add_child(_label("大 Boss（通关）掉落，只会是本流派的装备。★ 是特殊词条，强化某个招式或心法——没有对应招式 / 心法就用不上。", 15, Color("#cfc6ae")))
	# 五个部位
	var srow := _center_row(8)
	var worn: Array = []
	for slot in Gear.slot_ids():
		var sd := Gear.slot_def(slot)
		var bt: Button
		if gear_equip.has(slot):
			bt = _gear_button(str(gear_equip[slot]), 232, 74, true)
			bt.pressed.connect(func():
				gear_equip.erase(slot)
				_gear_refresh())
			worn.append(Gear.make(str(gear_equip[slot]), Save.school()))
		else:
			bt = _button("%s\n（空）" % sd["name"], Vector2(232, 74), 14)
			bt.disabled = true
		srow.add_child(bt)
	box.add_child(srow)
	var bon := Gear.bonuses(worn)
	var tot: Array = []
	for k in bon["stats"]:
		tot.append(Gear.stat_text(str(k), float(bon["stats"][k])))
	box.add_child(_label("已穿戴合计：" + ("　".join(tot) if not tot.is_empty() else "（无）") + "　　点击已穿戴的装备可卸下", 14, Color("#9ad0a0")))
	# 背包
	var inv: Array = []
	for c in Save.items():
		if not gear_discard.has(c):
			inv.append(c)
	inv.sort_custom(func(a, b): return int(Gear.parse(a)["rarity"]) > int(Gear.parse(b)["rarity"]))
	box.add_child(_label("背包 %d / %d%s" % [inv.size(), int(Data.gear["inventory_max"]), "　【丢弃模式：点击装备即丢弃，保存后生效】" if gear_drop_mode else "　点击装备穿上"], 18,
		Color("#f08070") if gear_drop_mode else Color("#c9a227")))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1210, 250)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	box.add_child(sc)
	if inv.is_empty():
		grid.add_child(_label("还没有装备。通关一次（击败大 Boss）就会掉落。", 16, Color("#8d8670")))
	for c in inv:
		var bt2 := _gear_button(str(c), 596, 52)
		if gear_equip.values().has(c):
			bt2.text = "✔ " + bt2.text
		bt2.pressed.connect(_gear_item_click.bind(str(c)))
		grid.add_child(bt2)
	gear_status = _label("", 16, Color("#cfc6ae"))
	gear_status.custom_minimum_size = Vector2(0, 22)
	box.add_child(gear_status)
	var btns := _center_row(16)
	var dm := _button("丢弃模式：%s" % ("开" if gear_drop_mode else "关"), Vector2(170, 44), 16)
	dm.pressed.connect(func():
		gear_drop_mode = not gear_drop_mode
		_gear_refresh())
	var save := _button("保存", Vector2(160, 44), 22)
	save.pressed.connect(func(): gear_saved.emit(gear_equip.duplicate(), gear_discard.duplicate()))
	var cancel := _button("返回  [Esc]", Vector2(160, 44), 18)
	cancel.pressed.connect(func(): modal_closed.emit())
	btns.add_child(dm)
	btns.add_child(save)
	btns.add_child(cancel)
	box.add_child(btns)


# ---------------------------------------------------------------------
# 小镇：对话框 / 百晓生图鉴 / 村子 HUD
# ---------------------------------------------------------------------

## NPC 对话：options 里每项 {label, enabled?}；数字键 1~9 或点击选择
func show_dialog(title: String, text: String, options: Array, portrait: Texture2D = null) -> void:
	hide_dialog()
	var pb := _panel_box()
	dialog_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	if portrait != null:
		var tr := TextureRect.new()
		tr.texture = portrait
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(portrait.get_width() * 2.0, portrait.get_height() * 2.0)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		head.add_child(tr)
	head.add_child(_label(title, 40))
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(620, 0)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color("#f3ead2"))
	box.add_child(body)
	dialog_count = options.size()
	for i in options.size():
		var o: Dictionary = options[i]
		var bt := _button("[%d] %s" % [i + 1, str(o["label"])], Vector2(620, 46), 20)
		bt.disabled = not bool(o.get("enabled", true))
		bt.pressed.connect(func(): dialog_option.emit(i))
		box.add_child(bt)
	dialog_panel.visible = true


func hide_dialog() -> void:
	if dialog_panel:
		dialog_panel.queue_free()
		dialog_panel = null
	dialog_count = 0


## 百晓生的图鉴：上面四个分类，左边条目，右边详情
func show_guide(cat: String = "play", index: int = 0) -> void:
	guide_cat = cat
	guide_index = index
	_build_guide()
	guide_panel.visible = true


func hide_guide() -> void:
	if guide_panel:
		guide_panel.visible = false


func _build_guide() -> void:
	if guide_panel:
		guide_panel.queue_free()
	var pb := _panel_box()
	guide_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("百晓册", 38))
	var tabs := _center_row(10)
	for c in Guide.CATEGORIES:
		var cid: String = c[0]
		var bt := _button(str(c[1]), Vector2(120, 40), 18)
		bt.toggle_mode = true
		bt.button_pressed = cid == guide_cat
		bt.pressed.connect(func(): show_guide(cid, 0))
		tabs.add_child(bt)
	box.add_child(tabs)
	var entries := Guide.entries(guide_cat)
	guide_index = clampi(guide_index, 0, maxi(0, entries.size() - 1))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	box.add_child(hb)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(300, 470)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	hb.add_child(left)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var b2 := Button.new()
		b2.text = str(e["title"])
		b2.custom_minimum_size = Vector2(280, 40)
		b2.focus_mode = Control.FOCUS_NONE
		b2.toggle_mode = true
		b2.button_pressed = i == guide_index
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.add_theme_font_size_override("font_size", 17)
		if str(e["icon_kind"]) != "":
			var ic := Data.icon(str(e["icon_kind"]), str(e["icon_id"]))
			if ic != null:
				b2.icon = ic
				b2.expand_icon = true
				b2.add_theme_constant_override("icon_max_width", 30)
		b2.pressed.connect(func(): show_guide(guide_cat, i))
		lv.add_child(b2)
	var right := ScrollContainer.new()
	right.custom_minimum_size = Vector2(640, 470)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	if not entries.is_empty():
		var cur: Dictionary = entries[guide_index]
		var title := Label.new()
		title.text = str(cur["title"])
		title.add_theme_font_size_override("font_size", 28)
		title.add_theme_color_override("font_color", Color("#c9a227"))
		rv.add_child(title)
		var txt := Label.new()
		txt.text = str(cur["text"])
		txt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		txt.custom_minimum_size = Vector2(610, 0)
		txt.add_theme_font_size_override("font_size", 17)
		txt.add_theme_color_override("font_color", Color("#f3ead2"))
		rv.add_child(txt)
	var back := _button("返回  [Esc]", Vector2(160, 44), 18)
	back.pressed.connect(func(): modal_closed.emit())
	var brow := _center_row()
	brow.add_child(back)
	box.add_child(brow)


## 村子里的提示：村名 / 玩家信息 / 操作提示
func show_town_hud(on: bool) -> void:
	if town_layer == null:
		town_layer = Control.new()
		town_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		town_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(town_layer)
		var title := Label.new()
		title.text = str(Data.town["name"])
		title.add_theme_font_size_override("font_size", 34)
		title.add_theme_color_override("font_color", Color("#f3ead2"))
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		title.add_theme_constant_override("outline_size", 8)
		title.set_anchors_preset(Control.PRESET_TOP_WIDE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(0, 10)
		town_layer.add_child(title)
		var hint := Label.new()
		hint.text = "WASD 移动　　靠近 NPC 按 E 交谈"
		hint.add_theme_font_size_override("font_size", 17)
		hint.add_theme_color_override("font_color", Color("#f3ead2"))
		hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		hint.add_theme_constant_override("outline_size", 6)
		hint.position = Vector2(16, 684)
		town_layer.add_child(hint)
		var who := Label.new()
		who.name = "Who"
		who.add_theme_font_size_override("font_size", 17)
		who.add_theme_color_override("font_color", Color("#f3ead2"))
		who.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		who.add_theme_constant_override("outline_size", 6)
		who.position = Vector2(16, 12)
		town_layer.add_child(who)
	var w := town_layer.get_node("Who") as Label
	var lv := int(Meta.progress(Save.meta_exp())["level"])
	var line := "局外 Lv%d" % lv
	if Net.logged_in():
		line = "玩家：%s　" % Net.nick + (("群：%s　" % Net.group_name) if Net.group_name != "" else "") + line
	w.text = line
	town_layer.visible = on


func show_pause() -> void:
	overlay_title.text = "暂停"
	overlay_body.text = "按 Esc 继续"
	overlay.visible = true


func show_end(won: bool) -> void:
	var w := world
	overlay_title.text = "天下第一！" if won else "江湖路远……"
	end_base = "%s\n\n存活 %s　等级 %d　击杀 %d\n本局得分 %s" % [
		"击败黑风寨主，名动江湖。" if won else "侠士请重新来过。",
		_fmt_time(w.time), w.level, w.kills, _commas(Score.compute(w.run_summary()))]
	var dd: Dictionary = w.run_summary()["difficulty"]
	if int(dd["count"]) != 100 or int(dd["hp"]) != 100 or int(dd["speed"]) != 100:
		end_base += "\n难度：数量 %d%% · 血量 %d%% · 速度 %d%%" % [dd["count"], dd["hp"], dd["speed"]]
	set_end_extra("")
	overlay.visible = true


## 结算界面的补充行（成绩上传结果等）
func set_end_extra(extra: String) -> void:
	var tail := "按 Enter / R 重新开始" + ("　·　按 B 查看排行榜" if Net.configured() else "")
	overlay_body.text = end_base + ("\n" + extra if extra != "" else "") + "\n\n" + tail


func hide_overlay() -> void:
	overlay.visible = false


func show_choices(choices: Array, title: String) -> void:
	choice_title.text = title
	for i in choice_buttons.size():
		var b := choice_buttons[i]
		if i < choices.size():
			var c: Dictionary = choices[i]
			b.text = "[%d] 【%s】%s\n      %s" % [i + 1, c["tag"], c["title"], c["desc"]]
			if c.has("color"):
				var col := Color(str(c["color"]))
				b.add_theme_color_override("font_color", col)
				b.add_theme_color_override("font_hover_color", col)
			else:
				b.remove_theme_color_override("font_color")
				b.remove_theme_color_override("font_hover_color")
			b.visible = true
		else:
			b.visible = false
	levelup_panel.visible = true


func hide_choices() -> void:
	levelup_panel.visible = false


# ---------------------------------------------------------------------
# HUD 绘制
# ---------------------------------------------------------------------

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]


func _bar(pos: Vector2, size: Vector2, ratio: float, color: Color, label: String) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(pos, size), Color(0.1, 0.1, 0.12, 0.55))
	canvas.draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), color)
	canvas.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.8), false, 2.0)
	canvas.draw_string(font, pos + Vector2(8, size.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


const ICON := 44.0
## 技能图标底色：按第一个标签区分（占位；以后换成正式图标）
const TAG_COLORS := {
	"贯穿": "#3a5a7a", "远程": "#3a5a7a", "近战": "#9a3a2a", "连击": "#9a3a2a",
	"范围": "#6a4a8a", "控制": "#7a5a2a", "追踪": "#2a7f7a", "蓄力": "#8a6a1a",
	"多向": "#2a6a5a", "防御": "#4a5a6a",
}


## 技能图标：底色方块 + 楷体首字 + 右下角层数（1~11 显示数字，12 层换成「极」）。
func _draw_skill_icon(pos: Vector2, s: SkillBase, maxed: bool) -> void:
	var tag: String = str(s.tags()[0])
	var base := Color(str(TAG_COLORS.get(tag, "#4a4a4a")))
	var r := Rect2(pos, Vector2(ICON, ICON))
	var bold := Data.font_bold
	var tex := Data.icon("skills", s.id)
	if tex != null:
		# 正式图标：浅色底板 + 图标；12 层时金边
		canvas.draw_rect(r, Color(0.16, 0.14, 0.12, 0.85))
		canvas.draw_texture_rect(tex, r.grow(-1.0), false)
		canvas.draw_rect(r, GameWorld.GOLD if maxed else Color(0.05, 0.05, 0.08, 0.9), false, 3.0 if maxed else 2.0)
	else:
		canvas.draw_rect(r, base)
		canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(ICON - 4, ICON - 4)), Color(1, 1, 1, 0.10))
		canvas.draw_rect(r, GameWorld.GOLD if maxed else Color(0.05, 0.05, 0.08, 0.9), false, 3.0 if maxed else 2.0)
		var glyph := str(s.def["name"]).substr(0, 1)
		canvas.draw_string_outline(bold, pos + Vector2(0, 31), glyph, HORIZONTAL_ALIGNMENT_CENTER, ICON, 28, 3, Color(0, 0, 0, 0.55))
		canvas.draw_string(bold, pos + Vector2(0, 31), glyph, HORIZONTAL_ALIGNMENT_CENTER, ICON, 28, Color("#f3ead2"))
	_draw_cd_sweep(r, s.cd_frac(), s.cd_secs())
	if maxed:
		# 12 层：右下角的层数数字直接换成「极」（楷体粗体，金字黑边）
		var p := pos + Vector2(ICON - 24, ICON - 3)
		canvas.draw_string_outline(bold, p, "极", HORIZONTAL_ALIGNMENT_RIGHT, 22, 19, 5, Color("#3a1f10"))
		canvas.draw_string(bold, p, "极", HORIZONTAL_ALIGNMENT_RIGHT, 22, 19, Color("#f0c050"))
	else:
		canvas.draw_string(bold, pos + Vector2(ICON - 20, ICON - 3), str(s.level),
			HORIZONTAL_ALIGNMENT_RIGHT, 18, 12, Color("#f3ead2"))


func toggle_hud() -> void:
	hud_expanded = not hud_expanded
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	(ui as Dictionary)["hud_expanded"] = hud_expanded
	Save.data["ui"] = ui
	Save.save_data()
	canvas.queue_redraw()


## 小地图：以主角为中心，显示 Boss / 精英 / 秘籍 / 还丹 / 吸星大法；超出范围的重要目标贴在边缘当指示
func _draw_minimap(pos: Vector2, size: float) -> void:
	var w := world
	var half := 900.0                           # 小地图覆盖的世界半径
	var k := size * 0.5 / half
	var center := pos + Vector2(size, size) * 0.5
	canvas.draw_rect(Rect2(pos, Vector2(size, size)), Color("#1c1812", 0.72))
	canvas.draw_rect(Rect2(pos, Vector2(size, size)), Color("#c9a227", 0.8), false, 2.0)
	for i in 2:
		var r := size * 0.5 * (0.5 + 0.5 * i)
		canvas.draw_arc(center, r, 0.0, TAU, 32, Color(1, 1, 1, 0.08), 1.0)

	var edge := func(p: Vector2) -> Array:      # 世界坐标 → 小地图坐标；返回 [位置, 是否在范围外]
		var d: Vector2 = (p - w.player_pos) * k
		var lim := size * 0.5 - 5.0
		var out_of: bool = absf(d.x) > lim or absf(d.y) > lim
		if out_of:
			var m := maxf(absf(d.x), absf(d.y))
			d = d / m * lim
		return [center + d, out_of]

	for pl in w.pills:
		var r1: Array = edge.call(pl["pos"])
		if not r1[1]:
			canvas.draw_circle(r1[0], 2.5, Color("#c2452d") if pl["kind"] == "small" else Color("#e0a82e"))
	for c in w.chests:
		var r2: Array = edge.call(c)
		canvas.draw_rect(Rect2((r2[0] as Vector2) - Vector2(3, 3), Vector2(6, 6)), GameWorld.GOLD)
	for e in w.enemies:
		if e.alive and (e.is_boss or e.is_elite):
			var r3: Array = edge.call(e.pos)
			if e.is_boss:
				canvas.draw_circle(r3[0], 5.0, Color("#8a4ac8"))
				canvas.draw_arc(r3[0], 5.0, 0.0, TAU, 12, Color("#f3ead2"), 1.5)
			elif not r3[1]:
				canvas.draw_circle(r3[0], 3.0, Color("#e08030"))
	for it in w.absorb_items:
		var r4: Array = edge.call(it["pos"])
		var pulse := 0.6 + 0.4 * sin(w.time * 6.0)
		var p4: Vector2 = r4[0]
		canvas.draw_circle(p4, 7.0 * pulse + 2.0, Color("#b98cff", 0.35))
		canvas.draw_circle(p4, 3.5, Color("#4fe0d0"))
		canvas.draw_arc(p4, 6.0, 0.0, TAU, 12, Color("#b98cff"), 2.0)
	# 主角（白点 + 朝向）
	canvas.draw_circle(center, 3.5, Color("#f3ead2"))
	canvas.draw_line(center, center + w.facing * 9.0, Color("#f3ead2"), 2.0)
	if w.vacuum_t > 0.0:
		canvas.draw_string(ThemeDB.fallback_font, pos + Vector2(0, size + 14.0), "吸星大法 %.1fs" % w.vacuum_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b98cff"))


func _plate(r: Rect2) -> void:
	canvas.draw_rect(r, Color("#e8dcc0", 0.82))
	canvas.draw_rect(r, Color("#3a2f1a", 0.55), false, 2.0)


## RO 式冷却转圈：深色阴影从 12 点钟方向开始，顺时针一点点转开；剩余秒数写在中间
func _draw_cd_sweep(r: Rect2, frac: float, secs: float) -> void:
	if frac <= 0.0:
		return
	var c := r.get_center()
	var big := r.size.x * 1.2
	var a0 := -PI * 0.5 + (1.0 - frac) * TAU        # 阴影剩下的部分：从这里转到一圈结束
	var pts := PackedVector2Array([c])
	var n := maxi(3, int(frac * 36.0))
	for i in n + 1:
		var ang := a0 + (-PI * 0.5 + TAU - a0) * float(i) / float(n)
		pts.append(c + Vector2.from_angle(ang) * big)
	var square := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
	for poly in Geometry2D.intersect_polygons(pts, square):
		canvas.draw_colored_polygon(poly, Color(0, 0, 0, 0.62))
	# 转圈的前沿线：像时钟指针，让「转到哪了」更清楚
	var dir := Vector2.from_angle(a0)
	var edge := r.size.x * 0.5 / maxf(absf(dir.x), absf(dir.y))        # 指针只画到图标边缘
	canvas.draw_line(c, c + dir * edge, Color(1, 1, 1, 0.4), 1.0)
	if secs >= 0.3:
		var txt := "%.1f" % secs if secs < 10.0 else str(int(secs))
		var f := Data.font_bold
		canvas.draw_string_outline(f, r.position + Vector2(0, r.size.y * 0.5 + 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, 4, Color(0, 0, 0, 0.9))
		canvas.draw_string(f, r.position + Vector2(0, r.size.y * 0.5 + 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color("#f3ead2"))


func _draw_hud() -> void:
	if world == null or world.stats.is_empty():
		return
	var w := world
	var font := ThemeDB.fallback_font
	var vw := canvas.size.x
	var ink := Color("#1d2a35")

	# 经验条（顶部通栏）
	var exp_frac := clampf(float(w.exp_now) / float(maxi(1, w.exp_next)), 0.0, 1.0)
	canvas.draw_rect(Rect2(0, 0, vw, 18), Color(0.1, 0.08, 0.05, 0.55))
	canvas.draw_rect(Rect2(0, 0, vw * exp_frac, 18), GameWorld.GOLD)
	canvas.draw_rect(Rect2(0, 0, vw * exp_frac, 6), Color(1, 0.95, 0.7, 0.35))
	canvas.draw_rect(Rect2(0, 0, vw, 18), Color(0.2, 0.15, 0.05, 0.9), false, 1.0)
	canvas.draw_string(font, Vector2(0, 14), "Lv %d　经验 %d / %d　（%d%%）" % [w.level, w.exp_now, w.exp_next, int(exp_frac * 100.0)],
		HORIZONTAL_ALIGNMENT_CENTER, vw, 13, Color("#2a1d05"))

	# 半透明宣纸底板：地图是深色的，HUD 的深色文字要有底
	var plate_h := 140.0 - 22.0 + 20.0 + w.skills.size() * (ICON + 14.0) + 8.0 + 20.0 + w.xinfa.size() * 26.0 + w.synergies.size() * 19.0 + 4.0 + 26.0 + _shi_extra_h()
	if not hud_expanded:
		plate_h = 108.0 - 22.0 + ICON + 6.0 + (30.0 if not w.xinfa.is_empty() else 0.0) + 20.0 + (22.0 if w.skills.has("dugu") else 0.0)
	_plate(Rect2(6, 22, 292, plate_h))
	_plate(Rect2(vw * 0.5 - 70.0, 22, 140, 40))
	_plate(Rect2(vw - 176.0, 22, 170, 30))
	_plate(Rect2(6, canvas.size.y - 40.0, 700, 34))
	_draw_minimap(Vector2(vw - 176.0, 58.0), 164.0)
	var max_hp := w.st("max_hp")
	var max_n := w.st("max_neili")
	_bar(Vector2(16, 26), Vector2(236, 20), w.hp / max_hp, GameWorld.VERMILION, "气血 %d/%d" % [int(w.hp), int(max_hp)])
	var realm := w.realm()
	var realm_col: Color = [Color("#6f86a8"), Color("#3aa6a0"), Color("#3fe0cf")][realm]
	_bar(Vector2(16, 52), Vector2(236, 20), w.neili / max_n, realm_col, "内力 %d/%d" % [int(w.neili), int(max_n)])
	# 三境分界线：虚 | 平 | 盈
	for t in [Data.T("xu_below"), w.ying_at()]:
		canvas.draw_line(Vector2(16 + 236 * float(t), 52), Vector2(16 + 236 * float(t), 72), Color(1, 1, 1, 0.9), 2.0)
	# 内力境界：收起时只显示一个字（盈 / 平 / 虚，入定时再加「定」）；详细说明在展开模式里
	var bold := Data.font_bold
	var realm_char: String = ["虚", "平", "盈"][realm]
	var realm_ink: Color = [Color("#3a5a8a"), Color("#6a5a3a"), Color("#0f8a7e")][realm]
	canvas.draw_string(bold, Vector2(258, 69), realm_char, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, realm_ink)
	if w.meditating():
		canvas.draw_string(bold, Vector2(279, 69), "定", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a0521d"))
	if w.shield > 0.0:
		canvas.draw_string(font, Vector2(258, 43), "盾%d" % int(w.shield), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#2a6f9a"))
	if hud_expanded:
		var detail := ""
		match realm:
			GameWorld.Realm.YING: detail = "盈境：伤害 +%d%%，招式自动催动" % int(round((Data.T("ying_dmg") + w.st("ying_dmg") - 1.0) * 100.0))
			GameWorld.Realm.PING: detail = "平境：没有加成"
			GameWorld.Realm.XU: detail = "虚境：回气加快，不能催动"
		if w.meditating():
			detail += "　入定中：回气更快、减伤"
		canvas.draw_string(font, Vector2(16, 120), detail, HORIZONTAL_ALIGNMENT_LEFT, 280, 13, Color("#1f6f6a"))

	canvas.draw_string(font, Vector2(16, 98), "Lv %d" % w.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	canvas.draw_string(font, Vector2(86, 98), "攻击 +%d%%　防御 %.1f" % [int(w.st("damage_pct") * 100.0), w.st("armor")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#6a5a3a"))

	# 计时 / 击杀
	canvas.draw_string(font, Vector2(vw * 0.5 - 60, 40), _fmt_time(w.time), HORIZONTAL_ALIGNMENT_CENTER, 120, 32, ink)
	canvas.draw_string(font, Vector2(vw - 160, 36), "击杀 %d" % w.kills, HORIZONTAL_ALIGNMENT_RIGHT, 144, 20, ink)

	# Boss 血条
	var by := 84.0
	for b in w.bosses:
		if b.alive:
			var bw := 520.0
			_bar(Vector2(vw * 0.5 - bw * 0.5, by), Vector2(bw, 18), b.hp / b.max_hp, Color("#5a2a7a"), b.boss_name)
			# 罡气条：青色细条；被打破后显示「虚弱」倒计时
			if b.weak_t > 0.0:
				canvas.draw_rect(Rect2(vw * 0.5 - bw * 0.5, by + 19, bw * b.weak_t / Data.T("break_t"), 5), GameWorld.GOLD)
				canvas.draw_string(font, Vector2(vw * 0.5 + bw * 0.5 + 8, by + 15), "虚弱 受伤 ×%.1f" % Data.T("break_dmg"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameWorld.GOLD)
			elif b.guard > 0.0:
				canvas.draw_rect(Rect2(vw * 0.5 - bw * 0.5, by + 19, bw * b.guard / b.guard_max, 5), Color("#4fe0d0"))
				canvas.draw_string(font, Vector2(vw * 0.5 + bw * 0.5 + 8, by + 15), "罡气 减伤 50%　催动 ×3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1f6f6a"))
			by += 30.0

	# 装备栏：技能 / 心法 / 轻功（Tab 展开 / 收起；收起时只显示图标，不挡视线）
	if not hud_expanded:
		var cx := 16.0
		for s2: SkillBase in w.skills.values():
			_draw_skill_icon(Vector2(cx, 108.0), s2, s2.upgrades.size() >= Data.max_upgrades)
			cx += ICON + 6.0
		var ry := 108.0 + ICON + 8.0
		cx = 16.0
		for id in w.xinfa:
			var xt2 := Data.icon("xinfa", id)
			if xt2 != null:
				canvas.draw_texture_rect(xt2, Rect2(cx, ry, 24, 24), false)
			canvas.draw_string(font, Vector2(cx + 16.0, ry + 25.0), str(w.xinfa[id]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#2a1d05"))
			cx += 34.0
		for sy2 in w.synergies:
			canvas.draw_string(font, Vector2(cx, ry + 18.0), "★" if bool(sy2["harmony"]) else "◇", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color("#a0521d") if bool(sy2["harmony"]) else Color("#1f6f6a"))
			cx += 18.0
		if w.skills.has("dugu"):
			canvas.draw_string(font, Vector2(16, ry + (30.0 if not w.xinfa.is_empty() else 0.0) + 14.0), "式 %d/%d　%s" % [w.shi_total(), int(Data.T("shi_stage3")) + 1, _stage_name()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GameWorld.VERMILION)
		canvas.draw_string(font, Vector2(16, plate_h + 22.0 - 6.0), "[Tab] 展开详情", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7a6a3a"))
	else:
		# 装备栏：技能 / 心法 / 轻功
		var y := 140.0
		canvas.draw_string(font, Vector2(16, y), "招式 %d/%d" % [w.skills.size(), GameWorld.MAX_SKILLS],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7a6a3a"))
		y += 20.0
		for s: SkillBase in w.skills.values():
			var maxed := s.upgrades.size() >= Data.max_upgrades
			var icon_pos := Vector2(16, y + 4.0)
			_draw_skill_icon(icon_pos, s, maxed)
			var star := " ★%d" % w.enhance_level if w.enhance_id == s.id else ""
			canvas.draw_string(font, icon_pos + Vector2(ICON + 8.0, 18.0), str(s.def["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
			canvas.draw_string(font, icon_pos + Vector2(ICON + 8.0, 36.0), "Lv%s%s" % ["极" if maxed else str(s.level), star],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameWorld.VERMILION if star != "" else Color("#6a5a3a"))
			y += ICON + 14.0
		if w.skills.has("dugu"):
			canvas.draw_string(font, Vector2(16, y + 8.0), "式 总层 %d（>%d 万法皆破 · >%d 真·独孤九剑）" % [w.shi_total(), int(Data.T("shi_stage2")), int(Data.T("shi_stage3"))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameWorld.VERMILION)
			y += 28.0
			for sid in w.shi:
				canvas.draw_string(font, Vector2(24, y), "%s　Lv%d" % [w.shi_name(str(sid)), int(w.shi[sid])], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#2a2a2a"))
				y += 18.0
		y += 8.0
		canvas.draw_string(font, Vector2(16, y), "心法 %d/%d" % [w.xinfa.size(), GameWorld.MAX_XINFA],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7a6a3a"))
		y += 20.0
		for id in w.xinfa:
			var xt := Data.icon("xinfa", id)
			if xt != null:
				canvas.draw_texture_rect(xt, Rect2(14, y - 15, 22, 22), false)
			canvas.draw_string(font, Vector2(42 if xt != null else 16, y), "%s Lv%d" % [Data.xinfa[id]["name"], w.xinfa[id]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
			y += 26.0 if xt != null else 21.0
		for sy in w.synergies:
			canvas.draw_string(font, Vector2(16, y), ("★ " if bool(sy["harmony"]) else "◇ ") + str(sy["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#a0521d") if bool(sy["harmony"]) else Color("#1f6f6a"))
			y += 19.0
		y += 4.0
		canvas.draw_string(font, Vector2(16, y), "轻功：%s" % w.qg["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#1f6f6a"))
		canvas.draw_string(font, Vector2(16, plate_h + 22.0 - 6.0), "[Tab] 收起", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7a6a3a"))

	# 操作提示 + 轻功次数
	var charges := int(w.qg.get("charges", 1))
	var hint := "轻功 [空格] "
	canvas.draw_string(font, Vector2(16, canvas.size.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#444444"))
	for i in charges:
		var c := Vector2(112 + i * 20, canvas.size.y - 22)
		canvas.draw_circle(c, 7.0, Color("#3aa6a0") if i < w.dash_charges else Color(0.3, 0.3, 0.3, 0.4))
	var burst_txt := "真气爆发 [E]　剩余 %d / %d 次" % [w.burst_left(), w.burst_max()]
	if w.burst_left() > 0:
		burst_txt += "　（消耗全部内力，当前威力 %d%%）" % int(w.burst_power() * 100.0) if w.can_burst() else "　（内力太少）"
	canvas.draw_string(font, Vector2(112 + charges * 20 + 12, canvas.size.y - 16), burst_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color("#a0521d") if w.can_burst() else Color("#444444"))


func _shi_extra_h() -> float:
	if not (world != null and world.skills.has("dugu")):
		return 0.0
	return 40.0 + (world.shi.size() * 18.0 if hud_expanded else 0.0)


func _stage_name() -> String:
	match world.dugu_stage():
		3: return "真·独孤九剑"
		2: return "万法皆破"
	return "初窥门径"
