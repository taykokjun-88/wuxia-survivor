class_name GameHud
extends CanvasLayer
## HUD：状态条、计时、Boss 血条；以及菜单/升级选择/结算浮层。全部由代码构建。

signal choice_selected(index: int)

var world: GameWorld
var canvas: Control
var overlay: Control
var overlay_title: Label
var overlay_body: Label
var levelup_panel: Control
var choice_buttons: Array[Button] = []


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

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 56)
	overlay_title.add_theme_color_override("font_color", Color("#f3ead2"))
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(overlay_title)
	overlay_body = Label.new()
	overlay_body.add_theme_font_size_override("font_size", 22)
	overlay_body.add_theme_color_override("font_color", Color("#f3ead2"))
	overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(overlay_body)


func _build_levelup() -> void:
	levelup_panel = Control.new()
	levelup_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.visible = false
	add_child(levelup_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "突破！选择一项领悟（按 1 / 2 / 3 或点击）"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#f3ead2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(640, 88)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): choice_selected.emit(i))
		box.add_child(b)
		choice_buttons.append(b)


func show_menu() -> void:
	overlay_title.text = "武侠幸存者"
	overlay_body.text = "原型 v0.1\n\nWASD 移动（自动攻击）　空格 轻功　E 真气爆发\n内力 ≥ 50% 时伤害 +25%\n\n按 Enter / 空格 开始"
	overlay.visible = true


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


func show_choices(choices: Array) -> void:
	for i in choice_buttons.size():
		var b := choice_buttons[i]
		if i < choices.size():
			var c: Dictionary = choices[i]
			b.text = "[%d] 【%s】%s\n      %s" % [i + 1, c["tag"], c["title"], c["desc"]]
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


func _draw_hud() -> void:
	if world == null:
		return
	var w := world
	var font := ThemeDB.fallback_font
	var vw := canvas.size.x

	# 经验条（顶部通栏）
	canvas.draw_rect(Rect2(0, 0, vw, 8), Color(0, 0, 0, 0.25))
	canvas.draw_rect(Rect2(0, 0, vw * float(w.exp_now) / float(w.exp_next), 8), GameWorld.GOLD)

	var max_hp := float(w.stats["max_hp"])
	var max_n := float(w.stats["max_neili"])
	_bar(Vector2(16, 20), Vector2(260, 20), w.hp / max_hp, GameWorld.VERMILION,
		"气血 %d/%d" % [int(w.hp), int(max_hp)])
	_bar(Vector2(16, 46), Vector2(260, 20), w.neili / max_n, Color("#3aa6a0"),
		"内力 %d/%d" % [int(w.neili), int(max_n)])
	# 50% 阈值刻度
	canvas.draw_line(Vector2(16 + 130, 46), Vector2(16 + 130, 66), Color(1, 1, 1, 0.9), 2.0)
	if w.neili >= max_n * GameWorld.NEILI_BONUS_THRESHOLD:
		canvas.draw_string(font, Vector2(286, 61), "内力充盈 伤害+25%", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1f6f6a"))

	canvas.draw_string(font, Vector2(16, 90), "Lv %d" % w.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#1d2a35"))

	# 计时 / 击杀
	canvas.draw_string(font, Vector2(vw * 0.5 - 60, 40), _fmt_time(w.time), HORIZONTAL_ALIGNMENT_CENTER, 120, 32, Color("#1d2a35"))
	canvas.draw_string(font, Vector2(vw - 160, 36), "击杀 %d" % w.kills, HORIZONTAL_ALIGNMENT_RIGHT, 144, 20, Color("#1d2a35"))

	# Boss 血条
	if w.boss != null and w.boss.alive:
		var bw := 520.0
		_bar(Vector2(vw * 0.5 - bw * 0.5, 84), Vector2(bw, 18), w.boss.hp / w.boss.max_hp, Color("#5a2a7a"), "海岛剑尊")

	# 已有武学
	var y := 118.0
	for id in w.owned:
		var def: Dictionary = Data.skills[id]
		canvas.draw_string(font, Vector2(16, y), "%s Lv%d" % [def["name"], w.owned[id]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2a2a2a"))
		y += 22.0

	# 操作提示
	var hint := "轻功 [空格]  %s" % ("冷却中" if w.dash_cd_t > 0.0 else "就绪")
	hint += "　真气爆发 [E]  %s" % ("就绪" if w.neili >= minf(float(w.stats["ult_cost"]), max_n) else "内力不足")
	canvas.draw_string(font, Vector2(16, canvas.size.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#444444"))
