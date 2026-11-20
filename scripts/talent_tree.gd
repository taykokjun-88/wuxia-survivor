class_name TalentTree
extends Control
## 天赋树：刚 / 柔 / 灵 三个并排的框，RO 技能树式排布（每个框 7 层、每层 2 个穴位，自上而下逐层解锁）。
## 玩家可以专注一个框往下点，也可以三个框分散投资。左键加点、右键减点（手机上用「减点模式」开关）。
## 框内背景：assets/ui/talent_bg/<流派>_<系>.jpg（流派 fist/sword/blade × 系 gang/rou/ling，共 9 张，可选）；
## 没有素材时，用该流派的立绘压暗后按系分别裁切 + 上色占位。
## 穴位图标：assets/ui/talent/node_{locked,open,ranked,maxed}.png（灰白色，按系着色）。

signal changed
signal hovered(node_id: String)

const ICON_DIR := "res://assets/ui/talent/"
const BOX_W := 404.0
const GAP := 12.0
const HEADER_H := 58.0
const ROW_H := 60.0
const ICON := 40.0
const COLORS := {"gang": "#d9573a", "rou": "#3fc2b6", "ling": "#a97be0"}

var work: Dictionary = {}          # 当前加点（id → 级数）
var level := 1                      # 局外等级（每级 2 点）
var school := ""                    # 当前流派（决定节点说明和背景）
var hover_id := ""
var remove_mode := false            # 手机：左键 = 减点
var icons: Dictionary = {}
var bgs: Dictionary = {}            # 系 → 背景图
var time_acc := 0.0
var _all: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for k in ["locked", "open", "ranked", "maxed"]:
		var path := ICON_DIR + "node_%s.png" % k
		if ResourceLoader.exists(path):
			icons[k] = load(path)
	setup(school)
	custom_minimum_size = tree_size()


func setup(school_id: String) -> void:
	school = school_id
	_all = Talents.nodes(school_id)
	bgs.clear()
	for b in Talents.branches():
		bgs[b] = _load_bg(b)


static func tree_size() -> Vector2:
	return Vector2(BOX_W * 3.0 + GAP * 2.0, HEADER_H + ROW_H * 7.0 + 10.0)


func _load_bg(branch: String) -> Texture2D:
	for ext in ["jpg", "png"]:
		var p := "res://assets/ui/talent_bg/%s_%s.%s" % [school, branch, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null


func box_rect(bi: int) -> Rect2:
	return Rect2(Vector2(bi * (BOX_W + GAP), 0.0), Vector2(BOX_W, size.y if size.y > 0.0 else tree_size().y))


## 节点中心（控件内坐标）
func node_pos(branch_i: int, row: int, idx: int) -> Vector2:
	var x := box_rect(branch_i).position.x + BOX_W * (0.3 if idx == 0 else 0.7)
	return Vector2(x, HEADER_H + ROW_H * (row + 0.5) - 6.0)


func _branch_index(branch: String) -> int:
	return Talents.branches().find(branch)


func node_at(p: Vector2) -> String:
	for id in _all:
		var n: Dictionary = _all[id]
		var c := node_pos(_branch_index(str(n["branch"])), int(n["row"]), _idx_in_row(id))
		if absf(p.x - c.x) < 62.0 and p.y > c.y - ICON * 0.5 - 6.0 and p.y < c.y + ICON * 0.5 + 22.0:
			return id
	return ""


func _idx_in_row(id: String) -> int:
	var n: Dictionary = _all[id]
	var rows: Array = Data.talents["branches"][n["branch"]]["rows"]
	var row: Array = rows[int(n["row"])]
	for i in row.size():
		if str(row[i]["id"]) == id:
			return i
	return 0


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var id := node_at(ev.position)
		if id != hover_id:
			hover_id = id
			hovered.emit(id)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		var id2 := node_at(ev.position)
		if id2 == "":
			return
		hover_id = id2
		var add: bool = (ev.button_index == MOUSE_BUTTON_LEFT) != remove_mode
		if ev.button_index != MOUSE_BUTTON_LEFT and ev.button_index != MOUSE_BUTTON_RIGHT:
			return
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			add = false
		if add and Talents.can_add(work, id2, level):
			work[id2] = int(work.get(id2, 0)) + 1
		elif not add and Talents.can_remove(work, id2, level):
			work[id2] = int(work[id2]) - 1
			if int(work[id2]) == 0:
				work.erase(id2)
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
	var mx := int(_all[id]["max"])
	if r >= mx:
		return "maxed"
	if r > 0:
		return "ranked"
	return "open" if Talents.can_add(work, id, level) else "locked"


## 这一层是否已经打通（本系更低层投入 ≥ 层号 × 门槛）
func row_open(branch: String, row: int) -> bool:
	var lower := 0
	for id in _all:
		var n: Dictionary = _all[id]
		if n["branch"] == branch and int(n["row"]) < row:
			lower += int(work.get(id, 0))
	return lower >= row * Talents.gate()


func info_text(id: String) -> String:
	if id == "":
		return "把鼠标移到穴位上查看。左键加点，右键减点；每一层需要本系更低层投入 ≥ 层号 × %d 点才解锁。三个框可以只专注一个，也可以分散投资。" % Talents.gate()
	var n: Dictionary = _all[id]
	var rank := int(work.get(id, 0))
	var state := "已满" if rank >= int(n["max"]) else ("可以加点" if Talents.can_add(work, id, level) else
		("本系投入还不够，解锁这一层需要本系更低层共 %d 点" % (int(n["row"]) * Talents.gate()) if not row_open(str(n["branch"]), int(n["row"])) else "天赋点用完了"))
	return "【%s · 第 %d 层】%s　%d / %d　（%s）\n%s" % [Data.talents["branches"][n["branch"]]["name"], int(n["row"]) + 1, n["name"], rank, int(n["max"]), state, n["desc"]]


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var bold: Font = Data.font_bold if Data.font_bold != null else font
	for bi in 3:
		var b: String = Talents.branches()[bi]
		var col := Color(COLORS[b])
		var rect := box_rect(bi)
		_draw_bg(rect, b, col, bi)
		draw_rect(rect, Color(col, 0.75), false, 2.5)
		# 标题：系名 + 说明 + 已投入
		var spent := Talents.branch_spent(work, b)
		draw_string(bold, rect.position + Vector2(16, 34), str(Data.talents["branches"][b]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(col.lightened(0.35), 1.0))
		draw_string(font, rect.position + Vector2(58, 22), str(Data.talents["branches"][b]["desc"]), HORIZONTAL_ALIGNMENT_LEFT, BOX_W - 160.0, 14, Color("#e8dfc5"))
		draw_string(bold, rect.position + Vector2(BOX_W - 112, 22), "%d / 30 点" % spent, HORIZONTAL_ALIGNMENT_RIGHT, 100.0, 18, Color("#fff6dc"))
		draw_line(rect.position + Vector2(12, HEADER_H - 4), rect.position + Vector2(BOX_W - 12, HEADER_H - 4), Color(col, 0.5), 1.5)
		# 层与层之间：门槛线（打通时点亮）+ 连线
		for r in 7:
			var y := HEADER_H + ROW_H * r
			if r > 0:
				var openr := row_open(b, r)
				draw_line(Vector2(rect.position.x + 14, y), Vector2(rect.end.x - 14, y), Color(col, 0.55 if openr else 0.18), 1.5)
				draw_string(font, Vector2(rect.position.x + 18, y + 13), "本系 ≥ %d 点" % (r * Talents.gate()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.lightened(0.3), 0.9 if openr else 0.45))
				for k in 2:
					var c0 := node_pos(bi, r - 1, k)
					var c1 := node_pos(bi, r, k)
					var lit := openr and int(work.get(_node_id(b, r - 1, k), 0)) > 0
					draw_line(c0 + Vector2(0, ICON * 0.5 + 10), c1 - Vector2(0, ICON * 0.5 + 2), Color(col, 0.85 if lit else 0.2), 3.0 if lit else 2.0)
		for r in 7:
			for k in 2:
				_draw_node(_node_id(b, r, k), bi, r, k, col, font)


func _node_id(branch: String, row: int, idx: int) -> String:
	return str(Data.talents["branches"][branch]["rows"][row][idx]["id"])


func _draw_bg(rect: Rect2, branch: String, col: Color, bi: int) -> void:
	draw_rect(rect, Color(0.05, 0.05, 0.06, 0.95))
	var tex: Texture2D = bgs.get(branch)
	var placeholder := false
	if tex == null:                                    # 占位：流派立绘，三个框各取不同的部位
		var path := str(Data.schools.get(school, {}).get("portrait", ""))
		if path != "" and ResourceLoader.exists(path):
			tex = load(path)
			placeholder = true
	if tex != null:
		var ts := tex.get_size()
		var want := rect.size.x / rect.size.y
		var src := Rect2(Vector2.ZERO, ts)
		if placeholder:
			var zoom := 1.0 + 0.35 * float(bi)
			var sw := ts.x / zoom
			var sh := sw / want
			if sh > ts.y:
				sh = ts.y
				sw = sh * want
			src = Rect2(Vector2((ts.x - sw) * 0.5, minf(ts.y - sh, ts.y * 0.1 * float(bi))), Vector2(sw, sh))
		elif ts.x / ts.y > want:
			src.size.x = ts.y * want
			src.position.x = (ts.x - src.size.x) * 0.5
		else:
			src.size.y = ts.x / want
			src.position.y = (ts.y - src.size.y) * 0.5
		draw_texture_rect_region(tex, rect, src, Color(1, 1, 1, 0.9))
	draw_rect(rect, Color(0.04, 0.04, 0.05, 0.4 if not placeholder else 0.6))   # 压暗，保证字和穴位看得清
	draw_rect(rect, Color(col, 0.10))


func _draw_node(id: String, bi: int, row: int, idx: int, col: Color, font: Font) -> void:
	var c := node_pos(bi, row, idx)
	var st := state_of(id)
	var n: Dictionary = _all[id]
	var rank := int(work.get(id, 0))
	var mx := int(n["max"])
	var rr := ICON * 0.5
	if id == hover_id:
		draw_rect(Rect2(c - Vector2(66, ICON * 0.5 + 6.0), Vector2(132, ICON + 30.0)), Color(1, 1, 1, 0.08))
	if icons.has(st):
		var sz := ICON * 1.15
		var tint := col if st != "locked" else Color(1, 1, 1, 0.55)
		draw_texture_rect(icons[st], Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, tint)
	else:
		match st:
			"locked":
				draw_circle(c, rr, Color(0.12, 0.11, 0.1, 0.8))
				draw_arc(c, rr, 0.0, TAU, 28, Color(0.45, 0.42, 0.38, 0.7), 2.0)
			"open":
				draw_circle(c, rr, Color(0.1, 0.09, 0.08, 0.88))
				draw_arc(c, rr, 0.0, TAU, 28, Color(col, 0.55 + 0.35 * sin(time_acc * 3.0 + c.x)), 2.5)
			"ranked":
				draw_circle(c, rr, Color(col, 0.38))
				draw_arc(c, rr, 0.0, TAU, 28, col, 3.0)
				draw_arc(c, rr + 3.0, -PI * 0.5, -PI * 0.5 + TAU * float(rank) / float(mx), 28, Color("#f3ead2", 0.9), 2.5)
			"maxed":
				draw_circle(c, rr + 5.0, Color("#c9a227", 0.25))
				draw_circle(c, rr, col)
				draw_arc(c, rr, 0.0, TAU, 28, Color("#c9a227"), 3.5)
	var name_col := Color("#fff6dc") if st == "ranked" or st == "maxed" else (Color("#e8dfc5") if st == "open" else Color("#8d8670"))
	draw_string(font, c + Vector2(-62, ICON * 0.5 + 12.0), str(n["name"]), HORIZONTAL_ALIGNMENT_CENTER, 124.0, 13, name_col)
	var txt := "%d" % rank if mx == 1 and rank > 0 else ("%d/%d" % [rank, mx])
	draw_string(font, c + Vector2(-20, 5), txt, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 12, Color("#fff6dc") if rank > 0 else Color(0.8, 0.77, 0.7, 0.8))
	if id == hover_id:
		draw_arc(c, rr + 7.0, 0.0, TAU, 28, Color("#fff6dc", 0.95), 2.0)
