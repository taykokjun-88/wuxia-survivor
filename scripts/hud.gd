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
var meta_work: Dictionary = {}
var meta_status: Label
var talents_panel: Control
var talents_work: Dictionary = {}
var talents_status: Label
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


func setup(w: GameWorld) -> void:
	world = w
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
	dim.color = Color(0.05, 0.05, 0.08, 0.62)
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
	box.add_child(_label("武侠幸存者", 52))
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

	var start := Button.new()
	start.text = "开始闯荡  [Enter]"
	start.custom_minimum_size = Vector2(260, 48)
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(confirm_loadout)
	var redo := Button.new()
	redo.text = "重新创建角色"
	redo.custom_minimum_size = Vector2(150, 48)
	redo.focus_mode = Control.FOCUS_NONE
	redo.pressed.connect(func(): recreate_requested.emit())
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 16)
	srow.add_child(start)
	srow.add_child(redo)
	var mp := Meta.progress(Save.meta_exp())
	var free_pts: int = Meta.points_total(int(mp["level"])) - Meta.points_used(Save.meta_alloc())
	var growth := _button("角色成长 Lv%d%s" % [mp["level"], ("　·%d点未分配" % free_pts) if free_pts > 0 else ""], Vector2(230, 48), 18)
	growth.pressed.connect(func(): meta_open_requested.emit())
	srow.add_child(growth)
	var gbtn := _button("装备（%d）" % Save.items().size(), Vector2(130, 48), 18)
	gbtn.pressed.connect(func(): gear_open_requested.emit())
	srow.add_child(gbtn)
	box.add_child(srow)
	if Net.configured():
		var xrow := _center_row(12)
		var who_text := "玩家：%s" % Net.nick
		if Net.group_name != "":
			who_text += "　群：%s" % Net.group_name
		var who := _label(who_text, 16, Color("#cfc6ae"))
		xrow.add_child(who)
		var bb := _button("排行榜", Vector2(120, 38), 16)
		bb.pressed.connect(func(): board_open_requested.emit())
		xrow.add_child(bb)
		if Net.logged_in():
			var fb := _button("反馈", Vector2(100, 38), 16)
			fb.pressed.connect(func(): feedback_open_requested.emit())
			xrow.add_child(fb)
		var acc := _button("退出登录", Vector2(130, 38), 16)
		acc.pressed.connect(func(): account_requested.emit())
		xrow.add_child(acc)
		box.add_child(xrow)


func confirm_create() -> void:
	character_created.emit(sel_school)


func confirm_loadout() -> void:
	loadout_confirmed.emit(sel_starter, sel_qg)


func show_create() -> void:
	_build_create()
	create_panel.visible = true
	overlay.visible = false


func hide_create() -> void:
	if create_panel:
		create_panel.visible = false


func show_loadout(school_id: String) -> void:
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


func _talent_click(id: String, delta: int, level: int) -> void:
	if delta > 0 and Talents.can_add(talents_work, id, level):
		talents_work[id] = int(talents_work.get(id, 0)) + 1
	elif delta < 0 and Talents.can_remove(talents_work, id, level):
		talents_work[id] = int(talents_work[id]) - 1
		if int(talents_work[id]) == 0:
			talents_work.erase(id)
	else:
		return
	_build_talents()
	talents_panel.visible = true


func _build_talents() -> void:
	if talents_panel:
		talents_panel.queue_free()
	var pb := _panel_box()
	talents_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_theme_constant_override("separation", 6)
	var level := Meta.level_of(Save.meta_exp())
	var free_pts := Talents.total_points(level) - Talents.spent(talents_work)
	box.add_child(_label("天赋树", 36))
	box.add_child(_label("可用天赋点 %d　（局外等级 %d）　左键加点，右键减点；每层需要本系更低层投入 ≥ 层号 × %d 点" % [
		free_pts, level, Talents.gate()], 16, Color("#9ad0a0") if free_pts > 0 else Color("#cfc6ae")))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cols)
	for b in Talents.branches():
		var bd: Dictionary = Data.talents["branches"][b]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		cols.add_child(col)
		col.add_child(_label("%s　%d / 35" % [bd["name"], Talents.branch_spent(talents_work, b)], 24, Color("#c9a227")))
		col.add_child(_label(str(bd["desc"]), 13, Color("#8d8670")))
		var rows: Array = bd["rows"]
		for r in rows.size():
			var rw := HBoxContainer.new()
			rw.add_theme_constant_override("separation", 6)
			col.add_child(rw)
			for n in rows[r]:
				var id: String = n["id"]
				var rank := int(talents_work.get(id, 0))
				var bt := Button.new()
				bt.custom_minimum_size = Vector2(172, 46)
				bt.clip_text = true
				bt.focus_mode = Control.FOCUS_NONE
				bt.add_theme_font_size_override("font_size", 13)
				bt.text = "%s  %d/%d\n%s" % [n["name"], rank, n["max"], n["desc"]]
				bt.tooltip_text = "%s（第 %d 层）\n%s" % [n["name"], r + 1, n["desc"]]
				var open := Talents.can_add(talents_work, id, level) or rank > 0
				if rank >= int(n["max"]):
					bt.add_theme_color_override("font_color", Color("#c9a227"))
				elif rank > 0:
					bt.add_theme_color_override("font_color", Color("#9ad0a0"))
				elif not Talents.can_add(talents_work, id, level):
					bt.modulate = Color(1, 1, 1, 0.45)
				bt.disabled = not open
				bt.pressed.connect(_talent_click.bind(id, 1, level))
				bt.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
						_talent_click(id, -1, level))
				rw.add_child(bt)
	talents_status = _label("", 16, Color("#cfc6ae"))
	talents_status.custom_minimum_size = Vector2(0, 22)
	box.add_child(talents_status)
	var btns := _center_row(16)
	var reset := _button("全部重置", Vector2(150, 44), 18)
	reset.pressed.connect(func():
		talents_work = {}
		_build_talents()
		talents_panel.visible = true)
	var save := _button("保存", Vector2(160, 44), 22)
	save.pressed.connect(func(): talents_saved.emit(talents_work.duplicate()))
	var cancel := _button("返回  [Esc]", Vector2(160, 44), 18)
	cancel.pressed.connect(func(): modal_closed.emit())
	btns.add_child(reset)
	btns.add_child(save)
	btns.add_child(cancel)
	box.add_child(btns)


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


func show_pause() -> void:
	overlay_title.text = "暂停"
	overlay_body.text = "按 Esc 继续"
	overlay.visible = true


func show_end(won: bool) -> void:
	var w := world
	overlay_title.text = "天下第一！" if won else "江湖路远……"
	end_base = "%s\n\n存活 %s　等级 %d　击杀 %d\n本局得分 %s" % [
		"击败海岛剑尊，名动江湖。" if won else "侠士请重新来过。",
		_fmt_time(w.time), w.level, w.kills, _commas(Score.compute(w.run_summary()))]
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
	canvas.draw_rect(r, base)
	canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(ICON - 4, ICON - 4)), Color(1, 1, 1, 0.10))
	canvas.draw_rect(r, GameWorld.GOLD if maxed else Color(0.05, 0.05, 0.08, 0.9), false, 3.0 if maxed else 2.0)
	var glyph := str(s.def["name"]).substr(0, 1)
	var bold := Data.font_bold
	canvas.draw_string_outline(bold, pos + Vector2(0, 31), glyph, HORIZONTAL_ALIGNMENT_CENTER, ICON, 28, 3, Color(0, 0, 0, 0.55))
	canvas.draw_string(bold, pos + Vector2(0, 31), glyph, HORIZONTAL_ALIGNMENT_CENTER, ICON, 28, Color("#f3ead2"))
	if maxed:
		# 12 层：右下角的层数数字直接换成「极」（楷体粗体，金字黑边）
		var p := pos + Vector2(ICON - 24, ICON - 3)
		canvas.draw_string_outline(bold, p, "极", HORIZONTAL_ALIGNMENT_RIGHT, 22, 19, 5, Color("#3a1f10"))
		canvas.draw_string(bold, p, "极", HORIZONTAL_ALIGNMENT_RIGHT, 22, 19, Color("#f0c050"))
	else:
		canvas.draw_string(bold, pos + Vector2(ICON - 20, ICON - 3), str(s.level),
			HORIZONTAL_ALIGNMENT_RIGHT, 18, 12, Color("#f3ead2"))


func _draw_hud() -> void:
	if world == null or world.stats.is_empty():
		return
	var w := world
	var font := ThemeDB.fallback_font
	var vw := canvas.size.x
	var ink := Color("#1d2a35")

	# 经验条（顶部通栏）
	canvas.draw_rect(Rect2(0, 0, vw, 8), Color(0, 0, 0, 0.25))
	canvas.draw_rect(Rect2(0, 0, vw * float(w.exp_now) / float(w.exp_next), 8), GameWorld.GOLD)

	var max_hp := w.st("max_hp")
	var max_n := w.st("max_neili")
	_bar(Vector2(16, 20), Vector2(260, 20), w.hp / max_hp, GameWorld.VERMILION, "气血 %d/%d" % [int(w.hp), int(max_hp)])
	var realm := w.realm()
	var realm_col: Color = [Color("#6f86a8"), Color("#3aa6a0"), Color("#3fe0cf")][realm]
	_bar(Vector2(16, 46), Vector2(260, 20), w.neili / max_n, realm_col, "内力 %d/%d" % [int(w.neili), int(max_n)])
	# 三境分界线：虚 | 平 | 盈
	for t in [Data.T("xu_below"), w.ying_at()]:
		canvas.draw_line(Vector2(16 + 260 * float(t), 46), Vector2(16 + 260 * float(t), 66), Color(1, 1, 1, 0.9), 2.0)
	var realm_txt := ""
	match realm:
		GameWorld.Realm.YING: realm_txt = "盈 · 伤害+%d%%　催动招式" % int(round((Data.T("ying_dmg") + w.st("ying_dmg") - 1.0) * 100.0))
		GameWorld.Realm.XU: realm_txt = "虚 · 回气加快"
	if w.meditating():
		realm_txt = (realm_txt + "　" if realm_txt != "" else "") + "入定"
	if realm_txt != "":
		canvas.draw_string(font, Vector2(286, 61), realm_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1f6f6a"))
	if w.shield > 0.0:
		canvas.draw_string(font, Vector2(286, 35), "护盾 %d" % int(w.shield), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#2a6f9a"))

	canvas.draw_string(font, Vector2(16, 90), "Lv %d" % w.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	canvas.draw_string(font, Vector2(86, 90), "攻击 +%d%%　防御 %.1f" % [int(w.st("damage_pct") * 100.0), w.st("armor")],
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

	# 装备栏：技能 / 心法 / 轻功
	var y := 118.0
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
	y += 8.0
	canvas.draw_string(font, Vector2(16, y), "心法 %d/%d" % [w.xinfa.size(), GameWorld.MAX_XINFA],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7a6a3a"))
	y += 20.0
	for id in w.xinfa:
		canvas.draw_string(font, Vector2(16, y), "%s Lv%d" % [Data.xinfa[id]["name"], w.xinfa[id]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
		y += 21.0
	for sy in w.synergies:
		canvas.draw_string(font, Vector2(16, y), ("★ " if bool(sy["harmony"]) else "◇ ") + str(sy["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#a0521d") if bool(sy["harmony"]) else Color("#1f6f6a"))
		y += 19.0
	y += 4.0
	canvas.draw_string(font, Vector2(16, y), "轻功：%s" % w.qg["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#1f6f6a"))

	# 操作提示 + 轻功次数
	var charges := int(w.qg.get("charges", 1))
	var hint := "轻功 [空格] "
	canvas.draw_string(font, Vector2(16, canvas.size.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#444444"))
	for i in charges:
		var c := Vector2(112 + i * 20, canvas.size.y - 22)
		canvas.draw_circle(c, 7.0, Color("#3aa6a0") if i < w.dash_charges else Color(0.3, 0.3, 0.3, 0.4))
	var ult_ok := w.neili >= minf(w.st("ult_cost"), max_n)
	canvas.draw_string(font, Vector2(112 + charges * 20 + 12, canvas.size.y - 16),
		"真气爆发 [E] %s" % ("就绪" if ult_ok else "内力不足"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#444444"))
