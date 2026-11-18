class_name GameHud
extends CanvasLayer
## HUD：状态条、技能槽、计时、Boss 血条；以及开局选择/升级选择/结算浮层。全部由代码构建。

signal choice_selected(index: int)
signal loadout_confirmed(starter_id: String, qinggong_id: String)
signal character_created(school_id: String)
signal recreate_requested

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
var sel_school := "fist"
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
func _build_create() -> void:
	if create_panel:
		create_panel.queue_free()
	var pb := _panel_box()
	create_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_child(_label("创建角色", 52))
	box.add_child(_label("选择你的武学流派。流派决定可学的招式，创建后不可在局内更改。", 18, Color("#cfc6ae")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var group := ButtonGroup.new()
	for id in Data.schools:
		var sd: Dictionary = Data.schools[id]
		var enabled := bool(sd["enabled"])
		var b := Button.new()
		b.text = "%s\n%s" % [sd["name"], str(sd["desc"]) if enabled else "敬请期待"]
		b.custom_minimum_size = Vector2(200, 110)
		b.disabled = not enabled
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == sel_school
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): sel_school = id)
		row.add_child(b)
	var ok := Button.new()
	ok.text = "创建角色  [Enter]"
	ok.custom_minimum_size = Vector2(260, 48)
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_font_size_override("font_size", 22)
	ok.pressed.connect(confirm_create)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_child(ok)
	box.add_child(srow)


## 每局开局：起手招式 + 轻功（流派已在创建角色时确定）
func _build_loadout() -> void:
	if loadout_panel:
		loadout_panel.queue_free()
	var pb := _panel_box()
	loadout_panel = pb[0]
	var box: VBoxContainer = pb[1]
	box.add_child(_label("武侠幸存者", 52))
	box.add_child(_label("角色流派：%s　　WASD 移动（自动攻击）　空格 轻功　E 真气爆发　内力 ≥ 50%% 伤害 +25%%" % Data.schools[school]["name"],
		16, Color("#cfc6ae")))

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
	box.add_child(srow)


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


func show_pause() -> void:
	overlay_title.text = "暂停"
	overlay_body.text = "按 Esc 继续"
	overlay.visible = true


func show_end(won: bool) -> void:
	var w := world
	overlay_title.text = "天下第一！" if won else "江湖路远……"
	overlay_body.text = "%s\n\n存活 %s　等级 %d　击杀 %d\n\n按 Enter / R 重新开始" % [
		"击败海岛剑尊，名动江湖。" if won else "侠士请重新来过。",
		_fmt_time(w.time), w.level, w.kills]
	overlay.visible = true


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


## 技能图标：底色方块 + 楷体首字 + 层数；满层（12 层）时在图标上方显示小「极」字。
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
	canvas.draw_string(Data.font_bold, pos + Vector2(ICON - 20, ICON - 3), str(s.level),
		HORIZONTAL_ALIGNMENT_RIGHT, 18, 12, Color("#f3ead2"))
	if maxed:
		# 「极」：楷体粗体，金字黑边，居中在图标正上方
		var p := pos + Vector2(0, -5)
		canvas.draw_string_outline(bold, p, "极", HORIZONTAL_ALIGNMENT_CENTER, ICON, 18, 4, Color("#3a1f10"))
		canvas.draw_string(bold, p, "极", HORIZONTAL_ALIGNMENT_CENTER, ICON, 18, Color("#f0c050"))


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
	_bar(Vector2(16, 46), Vector2(260, 20), w.neili / max_n, Color("#3aa6a0"), "内力 %d/%d" % [int(w.neili), int(max_n)])
	canvas.draw_line(Vector2(16 + 130, 46), Vector2(16 + 130, 66), Color(1, 1, 1, 0.9), 2.0)
	if w.neili >= max_n * GameWorld.NEILI_BONUS_THRESHOLD:
		canvas.draw_string(font, Vector2(286, 61), "内力充盈 伤害+25%", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1f6f6a"))
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
			by += 24.0

	# 装备栏：技能 / 心法 / 轻功
	var y := 118.0
	canvas.draw_string(font, Vector2(16, y), "招式 %d/%d" % [w.skills.size(), GameWorld.MAX_SKILLS],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7a6a3a"))
	y += 20.0
	for s: SkillBase in w.skills.values():
		var maxed := s.upgrades.size() >= Data.max_upgrades
		var icon_pos := Vector2(16, y + 22.0)      # 图标上方留出 22px 给「极」
		_draw_skill_icon(icon_pos, s, maxed)
		var star := " ★%d" % w.enhance_level if w.enhance_id == s.id else ""
		canvas.draw_string(font, icon_pos + Vector2(ICON + 8.0, 18.0), str(s.def["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
		canvas.draw_string(font, icon_pos + Vector2(ICON + 8.0, 36.0), "Lv%d%s" % [s.level, star],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameWorld.VERMILION if star != "" else Color("#6a5a3a"))
		y += ICON + 30.0
	y += 8.0
	canvas.draw_string(font, Vector2(16, y), "心法 %d/%d" % [w.xinfa.size(), GameWorld.MAX_XINFA],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7a6a3a"))
	y += 20.0
	for id in w.xinfa:
		canvas.draw_string(font, Vector2(16, y), "%s Lv%d" % [Data.xinfa[id]["name"], w.xinfa[id]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
		y += 21.0
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
