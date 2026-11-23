class_name TalentGrid
extends TalentTree
## 按流派的 RO 式天赋树（目前只有武者）：三个框并排；每个框 4 列——前 3 列是该系 3 个招式各自的专属天赋链（带箭头连线），第 4 列是通用数值链，
## 巅峰在最下方居中。节点有「前置」（≥1 点 / 点满）和「层门槛」（本系其余节点已投入点数），都满足才能点。左键加点、右键减点。
## 数据：data/talent_trees.json（由 tools/gen_talent_trees.py 生成）；校验：Talents / 后端 Code.gs。

const G_BOX_W := 404.0
const G_HEADER := 66.0
const G_ROW := 47.0
const G_ICON := 32.0
const G_STRIP := 52.0
const G_ROWS := 9

var _tree: Dictionary = {}
var _ji_id := ""
var _gate_nodes: Dictionary = {}


func _ready() -> void:
	super._ready()
	custom_minimum_size = grid_size()


func setup(school_id: String) -> void:
	school = school_id
	_tree = Talents.tree(school_id)
	_all = Talents.nodes(school_id)
	_ji_id = str(_tree.get("ji", {}).get("id", ""))
	bgs.clear()
	for b in _tree.get("branches", {}):
		bgs[b] = _load_bg(b)


static func grid_h() -> float:
	return G_HEADER + G_ROW * G_ROWS + 8.0


static func grid_size() -> Vector2:
	return Vector2(G_BOX_W * 3.0 + GAP * 2.0, grid_h() + G_STRIP)


func _bi(branch: String) -> int:
	return ["gang", "rou", "ling"].find(branch)


## 每个框的列数（武者 / 刀客 / 杨家将都是 4 列；剑客「灵」系 6 列）；框宽按列数分配
func _ncols(bi: int) -> int:
	var b: String = ["gang", "rou", "ling"][bi]
	return int((_tree["branches"][b]["cols"] as Array).size())


func g_box(bi: int) -> Rect2:
	var total := 0
	for k in 3:
		total += _ncols(k)
	var avail := grid_size().x - GAP * 2.0
	var x := 0.0
	for k in bi:
		x += avail * float(_ncols(k)) / float(total) + GAP
	return Rect2(Vector2(x, 0.0), Vector2(avail * float(_ncols(bi)) / float(total), grid_h()))


func g_colw(bi: int) -> float:
	return g_box(bi).size.x / float(_ncols(bi))


func g_pos(n: Dictionary) -> Vector2:
	var bi := _bi(str(n["branch"]))
	var r := g_box(bi)
	return Vector2(r.position.x + g_colw(bi) * (float(n["col"]) + 0.5), G_HEADER + G_ROW * (float(n["row"]) - 0.5) - 3.0)


func g_ji_pos() -> Vector2:
	return Vector2(grid_size().x * 0.5, grid_h() + G_STRIP * 0.5 + 2.0)


func node_at(p: Vector2) -> String:
	if p.distance_to(g_ji_pos()) < 34.0:
		return _ji_id
	for id in _all:
		var n: Dictionary = _all[id]
		if n["branch"] == "ji":
			continue
		var c := g_pos(n)
		if absf(p.x - c.x) < minf(50.0, g_colw(_bi(str(n["branch"]))) * 0.5) and p.y > c.y - G_ICON * 0.5 - 4.0 and p.y < c.y + G_ICON * 0.5 + 16.0:
			return id
	return ""


func ji_unlocked() -> bool:
	return Talents.spent(work, school) - int(work.get(_ji_id, 0)) >= Talents.ji_need()


func _branch_sum(branch: String, except: String = "") -> int:
	var s := 0
	for id in _all:
		if _all[id]["branch"] == branch and id != except:
			s += int(work.get(id, 0))
	return s


## 节点还差什么（用于说明文字）；空串 = 条件都满足
func lacks(id: String) -> String:
	var n: Dictionary = _all[id]
	if n["branch"] == "ji":
		return "" if ji_unlocked() else "本流派其余节点要先投满 %d 点（现在 %d）" % [Talents.ji_need(), Talents.spent(work, school)]
	var out: Array[String] = []
	var bsum := _branch_sum(str(n["branch"]), id)
	if bsum < int(n["gate"]):
		out.append("本系其余节点要先投入 %d 点（现在 %d）" % [int(n["gate"]), bsum])
	for rq in n.get("req", []):
		var rid := str(rq[0])
		var have := int(work.get(rid, 0))
		var need := int(_all[rid]["max"]) if rq[1] == "full" else 1
		if have < need:
			out.append("前置「%s」要%s（现在 %d/%d）" % [_all[rid]["name"], "点满" if rq[1] == "full" else "至少 1 点", have, int(_all[rid]["max"])])
	if bool(n.get("peak", false)):
		var has_cap := false
		for id2 in _all:
			if _all[id2]["branch"] == n["branch"] and bool(_all[id2].get("cap", false)) and int(work.get(id2, 0)) > 0:
				has_cap = true
		if not has_cap:
			out.append("本系至少点亮一个终极")
	return "；".join(out)


func info_text(id: String) -> String:
	if id == "":
		return "把鼠标移到穴位上查看。左键加点，右键减点。每个节点要满足：①前置节点（≥1 点 / 点满，用连线表示：细线 ≥1 点、粗线 点满）；②本系其余节点已投入的点数达到该层门槛（框内横线上的数字）。三系容量共 150 点，满级最多 99 点，所以要取舍；点满 99 点后出现第 100 点「极意」。"
	var n: Dictionary = _all[id]
	var rank := int(work.get(id, 0))
	if n["branch"] == "ji":
		if not ji_unlocked() and rank == 0:
			return "【极意】本流派其余节点投满 99 点后出现，是每个职业专属的极强机制。（现在已投入 %d 点）" % Talents.spent(work, school)
		return "【极意】%s　%d / 1\n%s" % [n["name"], rank, n["desc"]]
	var tag := "巅峰" if bool(n.get("peak", false)) else ("终极" if bool(n.get("cap", false)) else "")
	var state := "已满"
	if rank < int(n["max"]):
		if Talents.can_add(work, id, level):
			state = "可以加点"
		else:
			var why := lacks(id)
			state = why if why != "" else "天赋点用完了"
	return "【%s%s】%s　%d / %d　（%s）\n%s" % [_tree["branches"][n["branch"]]["name"], "·" + tag if tag != "" else "", n["name"], rank, int(n["max"]), state, n["desc"]]


func state_of(id: String) -> String:
	var r := int(work.get(id, 0))
	var mx := int(_all[id]["max"])
	if r >= mx:
		return "maxed"
	if r > 0:
		return "ranked"
	return "open" if Talents.can_add(work, id, level) else "locked"


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var bold: Font = Data.font_bold if Data.font_bold != null else font
	var gates: Array = _tree.get("gates", [])
	for bi in 3:
		var b: String = ["gang", "rou", "ling"][bi]
		var bd: Dictionary = _tree["branches"][b]
		var col := Color(COLORS[b])
		var rect := g_box(bi)
		_draw_bg(rect, b, col, bi)
		draw_rect(rect, Color(col, 0.75), false, 2.5)
		draw_string(bold, rect.position + Vector2(14, 34), str(bd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(col.lightened(0.35), 1.0))
		draw_string(font, rect.position + Vector2(54, 20), str(bd["sub"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 160.0, 13, Color("#e8dfc5"))
		draw_string(font, rect.position + Vector2(54, 38), "起手：" + str(Data.skills.get(bd["starter"], {}).get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col.lightened(0.4), 0.9))
		draw_string(bold, rect.position + Vector2(rect.size.x - 112, 24), "%d / 50 点" % _branch_sum(b), HORIZONTAL_ALIGNMENT_RIGHT, 100.0, 17, Color("#fff6dc"))
		draw_line(rect.position + Vector2(12, G_HEADER - 3), rect.position + Vector2(rect.size.x - 12, G_HEADER - 3), Color(col, 0.5), 1.5)
		# 列名
		for ci in (bd["cols"] as Array).size():
			var cw := g_colw(bi)
			var cx := rect.position.x + cw * (ci + 0.5)
			draw_string(font, Vector2(cx - cw * 0.5, G_HEADER + 2), str(bd["cols"][ci]), HORIZONTAL_ALIGNMENT_CENTER, cw, 10, Color(col.lightened(0.3), 0.55))
		# 层门槛线：行 r（2~7、9）上方；该行所在层的门槛
		for r in [2, 3, 4, 5, 6, 7, 9]:
			var tier: int = r if r < 9 else 8
			var gy: float = G_HEADER + G_ROW * float(r - 1)
			var okg := _branch_sum(b) >= int(gates[tier - 1])
			draw_line(Vector2(rect.position.x + 10, gy), Vector2(rect.end.x - 10, gy), Color(col, 0.5 if okg else 0.16), 1.0)
			draw_string(font, Vector2(rect.position.x + 14, gy + 11), "≥%d" % int(gates[tier - 1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.lightened(0.3), 0.95 if okg else 0.45))
		# 前置连线
		for id in _all:
			var n: Dictionary = _all[id]
			if n["branch"] != b:
				continue
			for rq in n.get("req", []):
				var a: Vector2 = g_pos(_all[str(rq[0])])
				var c := g_pos(n)
				var have := int(work.get(str(rq[0]), 0))
				var lit := have >= (int(_all[str(rq[0])]["max"]) if rq[1] == "full" else 1)
				var w := 3.5 if rq[1] == "full" else 1.8
				draw_line(a + Vector2(0, G_ICON * 0.5 + 2), c - Vector2(0, G_ICON * 0.5 + 2), Color(col.lightened(0.2) if lit else col, 0.95 if lit else 0.22), w)
		# 巅峰与终极的汇聚线（视觉辅助，不是前置）：峰顶向本系终极各画一条淡线
		for id in _all:
			var n2: Dictionary = _all[id]
			if n2["branch"] == b and bool(n2.get("peak", false)):
				for id2 in _all:
					if _all[id2]["branch"] == b and bool(_all[id2].get("cap", false)):
						var lit2 := int(work.get(id2, 0)) > 0
						draw_line(g_pos(_all[id2]) + Vector2(0, G_ICON * 0.5 + 2), g_pos(n2) - Vector2(0, G_ICON * 0.5 + 2), Color("#e8c15a", 0.6 if lit2 else 0.12), 1.2)
		for id in _all:
			if _all[id]["branch"] == b:
				_draw_gnode(id, col, font, bd)
	_draw_gji(font, bold)


func _draw_gnode(id: String, col: Color, font: Font, bd: Dictionary) -> void:
	var n: Dictionary = _all[id]
	var c := g_pos(n)
	var st := state_of(id)
	var rank := int(work.get(id, 0))
	var mx := int(n["max"])
	var cap := bool(n.get("cap", false))
	var peak := bool(n.get("peak", false))
	var gold := Color("#e8c15a")
	var ring := gold if (cap or peak) else col
	var rr := G_ICON * 0.5 * (1.2 if peak else 1.0)
	if id == hover_id:
		draw_rect(Rect2(c - Vector2(minf(48.0, g_colw(_bi(str(n["branch"]))) * 0.5), G_ICON * 0.5 + 4.0), Vector2(minf(96.0, g_colw(_bi(str(n["branch"])))), G_ICON + 24.0)), Color(1, 1, 1, 0.08))
	draw_circle(c, rr, Color(0.08, 0.07, 0.07, 0.92))
	# 招式链节点用该招式的图标，通用链 / 巅峰用文字徽章
	var tex: Texture2D = null
	var cs: Array = bd["col_skills"]
	var ci := int(n["col"])
	var sk_id: String = str(cs[ci]) if (not peak and ci < cs.size()) else ""
	if sk_id != "":
		tex = Data.icon("skills", sk_id)
	var dim := 1.0 if st != "locked" else 0.35
	if tex != null:
		var s := rr * 1.7
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, dim))
	else:
		draw_string(font, c + Vector2(-rr, 5), "巅" if peak else ("通" if sk_id == "" else ""), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, 15, Color(gold if peak else col, dim))
	match st:
		"locked":
			draw_arc(c, rr, 0.0, TAU, 28, Color(0.45, 0.42, 0.38, 0.7), 2.0)
		"open":
			draw_arc(c, rr, 0.0, TAU, 28, Color(ring, 0.55 + 0.35 * sin(time_acc * 3.0 + c.x)), 2.5)
		"ranked":
			draw_arc(c, rr, 0.0, TAU, 28, Color(ring, 0.5), 2.5)
			draw_arc(c, rr + 3.0, -PI * 0.5, -PI * 0.5 + TAU * float(rank) / float(mx), 28, Color("#f3ead2", 0.95), 2.5)
		"maxed":
			draw_circle(c, rr + 4.0, Color(gold, 0.22))
			draw_arc(c, rr, 0.0, TAU, 28, gold, 3.5)
	if cap:                                              # 终极：金色小菱形角标
		var d := c + Vector2(rr * 0.85, -rr * 0.85)
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -5), d + Vector2(5, 0), d + Vector2(0, 5), d + Vector2(-5, 0)]), gold)
	var name_col := Color("#fff6dc") if st == "ranked" or st == "maxed" else (Color("#e8dfc5") if st == "open" else Color("#8d8670"))
	var lw := minf(100.0, g_colw(_bi(str(n["branch"]))))
	draw_string(font, c + Vector2(-lw * 0.5, G_ICON * 0.5 + 11.0), str(n["name"]), HORIZONTAL_ALIGNMENT_CENTER, lw, 12, name_col)
	draw_string(font, c + Vector2(rr - 8.0, rr + 1.0), "%d/%d" % [rank, mx] if mx > 1 else ("●" if rank > 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#fff6dc") if rank > 0 else Color(0.8, 0.77, 0.7, 0.7))
	if id == hover_id:
		draw_arc(c, rr + 6.0, 0.0, TAU, 28, Color("#fff6dc", 0.95), 2.0)


func _draw_gji(font: Font, bold: Font) -> void:
	var c := g_ji_pos()
	var gold := Color("#e8c15a")
	var rank := int(work.get(_ji_id, 0))
	var open := ji_unlocked() or rank > 0
	var n: Dictionary = _all[_ji_id]
	var strip := Rect2(Vector2(0, grid_h() + 4.0), Vector2(size.x, G_STRIP - 6.0))
	draw_rect(strip, Color(0.07, 0.06, 0.04, 0.75))
	draw_rect(strip, Color(gold, 0.45 if open else 0.15), false, 2.0)
	var pulse := 0.5 + 0.5 * sin(time_acc * 3.0)
	if open:
		draw_circle(c, 26.0 + 3.0 * pulse, Color(gold, 0.18 + 0.12 * pulse))
		draw_circle(c, 20.0, Color(gold, 0.95 if rank > 0 else 0.35))
		draw_arc(c, 20.0, 0.0, TAU, 32, gold, 3.0)
		draw_string(bold, c + Vector2(-20, 8), "极", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 22, Color("#3a2a05") if rank > 0 else Color("#fff6dc"))
		draw_string(bold, c + Vector2(32, -2), str(n["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, gold.lightened(0.2))
		draw_string(font, c + Vector2(32, 16), "已点亮" if rank > 0 else "可以加点：第 100 点", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8dfc5"))
	else:
		draw_circle(c, 20.0, Color(0.12, 0.11, 0.1, 0.85))
		draw_arc(c, 20.0, 0.0, TAU, 32, Color(0.45, 0.42, 0.38, 0.7), 2.0)
		draw_string(bold, c + Vector2(-20, 8), "极", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 22, Color(0.5, 0.47, 0.42, 0.8))
		draw_string(font, c + Vector2(32, 5), "极意：投满 99 点后出现（%d / %d）" % [Talents.spent(work, school), Talents.ji_need()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8d8670"))
	if _ji_id == hover_id:
		draw_arc(c, 27.0, 0.0, TAU, 32, Color("#fff6dc", 0.95), 2.0)
