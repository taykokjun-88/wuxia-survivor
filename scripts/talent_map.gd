class_name TalentMap
extends Control
## 天赋树的经脉图：人体剪影上六条经脉（刚：双臂两脉，柔：躯干两脉，灵：双腿两脉），
## 每条脉 7 个穴位（= 7 层，由丹田向外）。左键加点、右键减点。
##
## 美术：assets/ui/meridian_bg.png 或 .jpg（人体经络背景，可选）与 assets/ui/talent/node_{locked,open,ranked,maxed}.png（穴位图标，可选）。
## 没有素材时用程序绘制的占位图。穴位坐标在 data/game_data.json 的 talents.map。

signal changed
signal hovered(node_id: String)

const BG_PATHS := ["res://assets/ui/meridian_bg.png", "res://assets/ui/meridian_bg.jpg"]
const ICON_DIR := "res://assets/ui/talent/"
const NODE_R := 14.0

var work: Dictionary = {}          # 当前加点（id → 级数）
var level := 1                      # 局外等级（= 可用天赋点总数）
var hover_id := ""
var fig_scale := 0.92
var fig_origin := Vector2.ZERO
var pos_of: Dictionary = {}         # 节点 id → 图内坐标（未缩放）
var meridians: Array = []           # [{id, branch, name, color, pts:[Vector2×7], ids:[7 个节点 id]}]
var bg: Texture2D
var icons: Dictionary = {}
var time_acc := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	for bp in BG_PATHS:
		if ResourceLoader.exists(bp):
			bg = load(bp)
			break
	for k in ["locked", "open", "ranked", "maxed"]:
		var path := ICON_DIR + "node_%s.png" % k
		if ResourceLoader.exists(path):
			icons[k] = load(path)
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = fig_size() * fig_scale


func fig_size() -> Vector2:
	var s: Array = Data.talents["map"]["size"]
	return Vector2(float(s[0]), float(s[1]))


func _build_layout() -> void:
	meridians.clear()
	pos_of.clear()
	var m: Dictionary = Data.talents["map"]
	var w := fig_size().x
	for mer in m["meridians"]:
		var pts: Array[Vector2] = []
		for p in mer["points"]:
			var x := float(p[0])
			if str(mer["side"]) == "right":
				x = w - x
			pts.append(Vector2(x, float(p[1])))
		var ids: Array = []
		var rows: Array = Data.talents["branches"][mer["branch"]]["rows"]
		for r in rows.size():
			var node: Dictionary = rows[r][int(mer["idx"])]
			ids.append(node["id"])
			pos_of[node["id"]] = pts[r]
		meridians.append({"id": mer["id"], "branch": mer["branch"], "name": mer["name"],
			"color": Color(str(m["colors"][mer["branch"]])), "pts": pts, "ids": ids})


func dantian() -> Vector2:
	var d: Array = Data.talents["map"]["dantian"]
	return Vector2(float(d[0]), float(d[1]))


func to_screen(p: Vector2) -> Vector2:
	return fig_origin + p * fig_scale


func node_at(screen_pos: Vector2) -> String:
	var best := ""
	var best_d := (NODE_R + 4.0) * fig_scale + 3.0
	for id in pos_of:
		var d := to_screen(pos_of[id]).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var id := node_at(ev.position)
		if id != hover_id:
			hover_id = id
			hovered.emit(id)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and hover_id != "":
		if ev.button_index == MOUSE_BUTTON_LEFT and Talents.can_add(work, hover_id, level):
			work[hover_id] = int(work.get(hover_id, 0)) + 1
		elif ev.button_index == MOUSE_BUTTON_RIGHT and Talents.can_remove(work, hover_id, level):
			work[hover_id] = int(work[hover_id]) - 1
			if int(work[hover_id]) == 0:
				work.erase(hover_id)
		else:
			return
		changed.emit()
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover_id != "":
		hover_id = ""
		hovered.emit("")
		queue_redraw()


func _process(dt: float) -> void:
	if visible:
		time_acc += dt
		queue_redraw()


## 节点状态：locked（还不能点）/ open（可以加点）/ ranked（已有点数）/ maxed（已满）
func state_of(id: String) -> String:
	var r := int(work.get(id, 0))
	var mx := int(Talents.nodes()[id]["max"])
	if r >= mx:
		return "maxed"
	if r > 0:
		return "ranked"
	return "open" if Talents.can_add(work, id, level) else "locked"


func _draw() -> void:
	fig_scale = minf(size.x / fig_size().x, size.y / fig_size().y)
	fig_origin = (size - fig_size() * fig_scale) * 0.5
	_draw_background()
	var dt_pos := to_screen(dantian())
	# 经脉：暗线 + 已点亮的线段
	for mer in meridians:
		var col: Color = mer["color"]
		var pts: Array = mer["pts"]
		var chain: Array[Vector2] = [dantian()]
		chain.append_array(pts)
		for i in range(chain.size() - 1):
			draw_line(to_screen(chain[i]), to_screen(chain[i + 1]), Color(col, 0.22), 3.0 * fig_scale)
		# 点亮到「最高的已有点数的穴位」
		var lit := -1
		for r in 7:
			if int(work.get(mer["ids"][r], 0)) > 0:
				lit = r
		for i in range(lit + 1):
			var pulse := 0.65 + 0.35 * sin(time_acc * 3.0 - i * 0.6)
			draw_line(to_screen(chain[i]), to_screen(chain[i + 1]), Color(col, 0.35 * pulse), 9.0 * fig_scale)
			draw_line(to_screen(chain[i]), to_screen(chain[i + 1]), Color(col.lightened(0.35), 0.95), 3.5 * fig_scale)
	# 丹田
	var glow := 0.5 + 0.5 * sin(time_acc * 2.0)
	draw_circle(dt_pos, 26.0 * fig_scale, Color("#c9a227", 0.10 + 0.08 * glow))
	draw_arc(dt_pos, 17.0 * fig_scale, 0.0, TAU, 32, Color("#c9a227", 0.85), 2.5 * fig_scale)
	draw_arc(dt_pos, 9.0 * fig_scale, PI * 0.5, PI * 1.5, 16, Color("#f3ead2", 0.9), 3.0 * fig_scale)
	draw_arc(dt_pos, 9.0 * fig_scale, -PI * 0.5, PI * 0.5, 16, Color("#2b2b2b", 0.9), 3.0 * fig_scale)
	# 穴位
	var font := ThemeDB.fallback_font
	for mer in meridians:
		var col2: Color = mer["color"]
		for r in 7:
			_draw_node(str(mer["ids"][r]), col2, font)


func _draw_node(id: String, col: Color, font: Font) -> void:
	var c := to_screen(pos_of[id])
	var rr := NODE_R * fig_scale
	var st := state_of(id)
	var rank := int(work.get(id, 0))
	var mx := int(Talents.nodes()[id]["max"])
	if icons.has(st):
		var tex: Texture2D = icons[st]
		var sz := rr * 2.6
		draw_texture_rect(tex, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col if st != "locked" else Color(1, 1, 1, 0.6))
	else:
		match st:
			"locked":
				draw_circle(c, rr, Color(0.12, 0.11, 0.1, 0.75))
				draw_arc(c, rr, 0.0, TAU, 24, Color(0.45, 0.42, 0.38, 0.7), 2.0)
			"open":
				draw_circle(c, rr, Color(0.1, 0.09, 0.08, 0.85))
				draw_arc(c, rr, 0.0, TAU, 24, Color(col, 0.55 + 0.35 * sin(time_acc * 3.0 + c.x)), 2.5)
			"ranked":
				draw_circle(c, rr, Color(col, 0.35))
				draw_arc(c, rr, 0.0, TAU, 24, col, 3.0)
				draw_arc(c, rr + 3.0, -PI * 0.5, -PI * 0.5 + TAU * float(rank) / float(mx), 24, Color("#f3ead2", 0.9), 2.5)
			"maxed":
				draw_circle(c, rr + 5.0, Color("#c9a227", 0.22))
				draw_circle(c, rr, col)
				draw_arc(c, rr, 0.0, TAU, 24, Color("#c9a227"), 3.5)
	if rank > 0 or id == hover_id:
		var txt := "%d" % rank if mx == 1 else "%d/%d" % [rank, mx]
		draw_string(font, c + Vector2(-20, 4.5), txt, HORIZONTAL_ALIGNMENT_CENTER, 40.0, int(12.0 * maxf(fig_scale, 0.85)),
			Color("#fff6dc") if st != "open" and st != "locked" else Color("#cfc6ae"))
	if id == hover_id:
		draw_arc(c, rr + 6.0, 0.0, TAU, 28, Color("#fff6dc", 0.95), 2.0)


func _poly(pts: Array, mirror: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var x := float(p[0])
		out.append(to_screen(Vector2(fig_size().x - x if mirror else x, float(p[1]))))
	if mirror:
		out.reverse()
	return out


func _draw_background() -> void:
	var rect := Rect2(fig_origin, fig_size() * fig_scale)
	if bg != null:
		# 铺满并居中裁切：banana 出的比例不是正好 440:700 也不会变形
		var ts := bg.get_size()
		var want := rect.size.x / rect.size.y
		var src := Rect2(Vector2.ZERO, ts)
		if ts.x / ts.y > want:
			src.size.x = ts.y * want
			src.position.x = (ts.x - src.size.x) * 0.5
		else:
			src.size.y = ts.x / want
			src.position.y = (ts.y - src.size.y) * 0.5
		draw_texture_rect_region(bg, rect, src)
		return
	# 占位：深色底 + 淡淡的人形轮廓（形状在 data 的 talents.map.silhouette，版式参考图 docs/meridian_layout_guide.png 用同一份），
	# 等 banana 的经络图到位（assets/ui/meridian_bg.png）后自动换掉
	draw_rect(rect, Color(0.07, 0.07, 0.08, 0.55))
	var ink := Color(0.55, 0.5, 0.42, 0.16)
	var sil: Dictionary = Data.talents["map"]["silhouette"]
	var hd: Array = sil["head"]
	draw_circle(to_screen(Vector2(float(hd[0]), float(hd[1]))), float(hd[2]) * fig_scale, ink)
	for key in ["neck", "torso"]:
		draw_colored_polygon(_poly(sil[key], false), ink)
	for key in ["arm_left", "leg_left"]:
		draw_colored_polygon(_poly(sil[key], false), ink)
		draw_colored_polygon(_poly(sil[key], true), ink)
	draw_rect(rect, Color(0.5, 0.45, 0.35, 0.35), false, 1.5)
