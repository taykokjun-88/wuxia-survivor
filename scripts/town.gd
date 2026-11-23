class_name Town
extends Node2D
## 小镇（竹溪村）：可走动的像素风镇子。NPC 和建筑在 data 的 town 里定义；
## NPC 立绘来自 assets/town/npc/<sprite>.png，没有时画占位；建筑目前是程序绘制的像素风占位（等正式素材）。
## 本类只管「走动 / 碰撞 / 绘制 / 找最近的 NPC」；点开对话和各种界面由 main.gd 负责。

const TILE_T := 128                # 小镇地面瓦片的世界边长
const SPEED := 190.0
const NPC_REACH := 86.0          # 离 NPC 多近可以交谈
const PLAYER_R := 11.0

var player_pos := Vector2.ZERO
var facing := Vector2.DOWN
var input_move := Vector2.ZERO
var moving := false
var step_t := 0.0                # 脚步声计时
var time := 0.0

var _npc_meta: Dictionary = {}
var npcs: Array = []                  # [{id, name, title, pos, tex, building}]
var obstacles: Array[Rect2] = []      # 建筑 / 水井 / 摊位：不可穿过
var bounds := Rect2()
var map_art: MapArt
var sprite_anim: SpriteAnim
var hero_art: EnemyArt            # 村子专用的主角走路素材：hero_down / hero_up / hero_side（朝右，朝左时翻转）
var banner_font: Font
var building_art: Dictionary = {}    # 建筑 id → {tex, w, h, sign:[x, y, 宽]}（assets/town/buildings；没有素材的建筑用代码画）
var _school := ""
var _deco: Dictionary = {}           # 小镇装饰素材（树 / 灯笼柱 / 水井）：id → {tex, w, h}；没有素材时用代码画


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var b: Array = Data.town["bounds"]
	bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	map_art = MapArt.new()
	if not map_art.load_dir("res://assets/maps/town"):
		if not map_art.load_dir("res://assets/maps/black_wind"):
			map_art = null
	_load_deco()
	_load_buildings()
	var nmj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/town/npc/meta.json")) if FileAccess.file_exists("res://assets/town/npc/meta.json") else null
	_npc_meta = nmj if nmj is Dictionary else {}
	set_school("fist")
	banner_font = Data.font_bold
	for n in Data.town["npcs"]:
		var d: Dictionary = (n as Dictionary).duplicate(true)
		var p: Array = d["pos"]
		d["pos"] = Vector2(float(p[0]), float(p[1]))
		var path := "res://assets/town/npc/%s.png" % str(d["sprite"])
		d["tex"] = load(path) if ResourceLoader.exists(path) else null
		var nm: Dictionary = _npc_meta.get(str(d["sprite"]), {})
		if not nm.is_empty():
			d["tw"] = float(nm["w"])        # 世界尺寸（贴图可以比它大，高清素材缩小显示）
			d["th"] = float(nm["h"])
		npcs.append(d)
		_add_building_obstacle(d)
	obstacles.append(Rect2(-40, -110, 80, 70))          # 水井（挪到广场偏北，避开茶摊）
	reset_player()


## 主角形象跟随流派：村子走路素材 + 战斗动画（后者只作回退）
func set_school(school_id: String) -> void:
	if not Data.schools.has(school_id):
		school_id = "fist"
	if _school == school_id:
		return
	_school = school_id
	var sd: Dictionary = Data.schools[school_id]
	sprite_anim = SpriteAnim.new()
	if not sprite_anim.load_dir(str(sd.get("sprite_dir", "res://assets/sprites/player"))):
		sprite_anim = null
	hero_art = EnemyArt.new()
	if hero_art.load_dir(str(sd.get("town_hero_dir", "res://assets/town/hero"))) == 0:
		hero_art = null
	queue_redraw()


func _load_deco() -> void:
	var path := "res://assets/town/deco/meta.json"
	if not FileAccess.file_exists(path):
		return
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not js is Dictionary:
		return
	for id in js:
		var f := "res://assets/town/deco/%s" % str((js[id] as Dictionary)["file"])
		if ResourceLoader.exists(f):
			_deco[str(id)] = {"tex": load(f), "w": float(js[id]["w"]), "h": float(js[id]["h"])}


## 画一张装饰：脚底中心在 at，缩放 s
func _draw_deco(id: String, at: Vector2, s: float = 1.0) -> void:
	var d: Dictionary = _deco[id]
	var w := float(d["w"]) * s
	var h := float(d["h"]) * s
	draw_texture_rect(d["tex"], Rect2(at.x - w * 0.5, at.y - h + 4.0, w, h), false)


func _load_buildings() -> void:
	var path := "res://assets/town/buildings/meta.json"
	if not FileAccess.file_exists(path):
		return
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not js is Dictionary:
		return
	for id in js:
		var d: Dictionary = js[id]
		var f := "res://assets/town/buildings/%s" % str(d["file"])
		if ResourceLoader.exists(f):
			building_art[str(id)] = {"tex": load(f), "w": int(d["w"]), "h": int(d["h"]), "sign": d.get("sign", [0, 0, 0]), "plaque": bool(d.get("plaque", false))}


## 建筑素材：底边落在建筑矩形的底边，水平居中；木牌上写店名
func _draw_building_art(n: Dictionary, r: Rect2) -> bool:
	var key := str((n["building"] as Dictionary).get("art", ""))
	if not building_art.has(key):
		return false
	var a: Dictionary = building_art[key]
	var w := float(a["w"])
	var h := float(a["h"])
	var pos: Vector2 = n["pos"]
	var base_y := r.end.y + 10.0
	var tl := Vector2(pos.x - w * 0.5, base_y - h)
	draw_rect(Rect2(tl.x + w * 0.1, base_y - 10.0, w * 0.8, 14.0), Color(0, 0, 0, 0.18))
	draw_texture_rect(a["tex"], Rect2(tl, Vector2(w, h)), false)
	var sg: Array = a["sign"]
	var sign_w := float(sg[2])
	var sx := tl.x + float(sg[0])
	var sy := tl.y + float(sg[1])
	var txt := str((n["building"] as Dictionary)["sign"])
	var fs := int(clampf(sign_w / maxf(2.0, float(txt.length())) * 0.9, 14.0, 24.0))
	if bool(a.get("plaque", false)):         # 素材里没有现成的牌匾：画一块深色木牌托住店名
		var pr := Rect2(sx - sign_w * 0.5 - 6.0, sy - fs * 0.5 - 4.0, sign_w + 12.0, fs + 12.0)
		draw_rect(pr, Color("#3a2610", 0.92))
		draw_rect(pr, Color("#c9a227", 0.9), false, 2.0)
	draw_string_outline(banner_font, Vector2(sx - sign_w * 0.5, sy + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, sign_w, fs, 4, Color("#2a1a08"))
	draw_string(banner_font, Vector2(sx - sign_w * 0.5, sy + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, sign_w, fs, Color("#f0c050"))
	return true


func reset_player() -> void:
	var sp: Array = Data.town["spawn"]
	player_pos = Vector2(float(sp[0]), float(sp[1]))
	facing = Vector2.DOWN
	input_move = Vector2.ZERO


func building_rect(npc: Dictionary) -> Rect2:
	var bd: Dictionary = npc["building"]
	var pos: Vector2 = npc["pos"]
	if str(bd.get("kind", "")) == "stall":
		return Rect2(pos.x - 60.0, pos.y - 56.0, 120.0, 34.0)
	var w := float(bd["w"])
	var h := float(bd["h"])
	return Rect2(pos.x - w * 0.5, pos.y - 34.0 - h, w, h)


func _add_building_obstacle(npc: Dictionary) -> void:
	var r := building_rect(npc)
	var akey := str((npc["building"] as Dictionary).get("art", ""))
	if building_art.has(akey):
		# 按素材实际绘制的范围做碰撞：底边与绘制一致（见 _draw_building_art），占下半部分（屋檐以上可以走到后面去）
		var a: Dictionary = building_art[akey]
		var bw := float(a["w"])
		var bh := float(a["h"])
		var base_y := r.end.y + 10.0
		var pos0: Vector2 = npc["pos"]
		obstacles.append(Rect2(pos0.x - bw * 0.46, base_y - bh * 0.42, bw * 0.92, bh * 0.42))
		return
	if str((npc["building"] as Dictionary).get("kind", "")) == "stall":
		obstacles.append(r)
	else:
		obstacles.append(Rect2(r.position + Vector2(0, 40), r.size - Vector2(0, 40)))   # 屋顶部分可以走到后面去（视觉上被遮住不要紧）


func _blocked(p: Vector2) -> bool:
	if not bounds.grow(-PLAYER_R).has_point(p):
		return true
	for r in obstacles:
		if r.grow(PLAYER_R * 0.8).has_point(p):
			return true
	for n in npcs:
		if (n["pos"] as Vector2).distance_to(p) < 22.0:
			return true
	return false


func step(dt: float) -> void:
	time += dt
	var m := input_move
	if m.length() > 1.0:
		m = m.normalized()
	moving = m.length() > 0.1
	if moving:
		step_t -= dt
		if step_t <= 0.0:
			step_t = 0.36
			Sfx.play("footstep", 0.06, 0.0)
		facing = m.normalized()
		var d := m * SPEED * dt
		# 分轴移动：贴着墙能滑过去
		if not _blocked(player_pos + Vector2(d.x, 0)):
			player_pos.x += d.x
		if not _blocked(player_pos + Vector2(0, d.y)):
			player_pos.y += d.y
	queue_redraw()


## 最近的、在交谈范围内的 NPC；没有返回空字典
func near_npc() -> Dictionary:
	var best := {}
	var best_d := NPC_REACH
	for n in npcs:
		var d := (n["pos"] as Vector2).distance_to(player_pos)
		if d < best_d:
			best_d = d
			best = n
	return best


# ---------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------

func _vis(p: Vector2, margin: float = 120.0) -> bool:
	return absf(p.x - player_pos.x) < 700.0 + margin and absf(p.y - player_pos.y) < 420.0 / Depth.tilt + margin


func _draw() -> void:
	_draw_ground()
	for n in npcs:
		if _vis(n["pos"], 260.0):
			Depth.upright(self, (n["pos"] as Vector2) + Vector2(0, 20))     # 建筑站直（以门前为支点）
			_draw_building(n)
			Depth.flat(self)
	_draw_well()
	_draw_decor()
	# NPC 和主角按脚底的 y 排序，谁靠下谁盖在上面
	var items: Array = []
	for n in npcs:
		items.append({"y": (n["pos"] as Vector2).y, "npc": n})
	items.append({"y": player_pos.y, "npc": null})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	var near := near_npc()
	for it in items:
		if it["npc"] == null:
			_draw_player()
		else:
			_draw_npc(it["npc"], not near.is_empty() and near["id"] == it["npc"]["id"])


func _tile_kind(cx: int, cy: int) -> int:
	## 小镇地面瓦片（assets/maps/town）：0 夯土 / 1 石板路 / 2 泥地杂草 / 3 青石广场
	var c := Vector2(cx * TILE_T + TILE_T / 2, cy * TILE_T + TILE_T / 2)
	if absf(c.x) < 80.0 or absf(c.y + 300.0) < 60.0 or absf(c.y - 200.0) < 60.0:
		if absf(c.y) < 800.0:
			return 1                 # 石板路
	if (c - Vector2(0, 40)).length() < 190.0:
		return 3                     # 青石广场
	if map_art != null and map_art.noise(cx * 0.12, cy * 0.12, 5) > 0.72:
		return 0                     # 夯土（少量斑块）
	return 2                         # 泥地 + 杂草（大面积基底）


func _draw_ground() -> void:
	if map_art == null:
		draw_rect(Rect2(player_pos - Vector2(900, 600 / Depth.tilt), Vector2(1800, 1200 / Depth.tilt)), Color("#6a5a3a"))
		return
	var x0 := int(floorf((player_pos.x - 700.0) / TILE_T))
	var x1 := int(floorf((player_pos.x + 700.0) / TILE_T))
	var y0 := int(floorf((player_pos.y - 420.0 / Depth.tilt) / TILE_T))
	var y1 := int(floorf((player_pos.y + 420.0 / Depth.tilt) / TILE_T))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2(cx * TILE_T + TILE_T / 2, cy * TILE_T + TILE_T / 2)
			if not bounds.grow(70.0).has_point(c):
				draw_rect(Rect2(cx * TILE_T, cy * TILE_T, TILE_T, TILE_T), Color("#2a3a22"))      # 镇外：深绿
				continue
			var k := _tile_kind(cx, cy)
			var o := map_art._h(cx, cy, 77) & 7
			draw_texture_rect(map_art.ground_var[mini(k, map_art.ground_var.size() - 1)][o], Rect2(cx * TILE_T, cy * TILE_T, TILE_T, TILE_T), false)
	# 镇边的栅栏
	var edge := Color("#5a3f22")
	for sx in [bounds.position.x - 6.0, bounds.end.x - 2.0]:
		draw_rect(Rect2(sx, bounds.position.y, 8, bounds.size.y), edge)
	for sy in [bounds.position.y - 6.0, bounds.end.y - 2.0]:
		draw_rect(Rect2(bounds.position.x, sy, bounds.size.x, 8), edge)


## 像素风「圆」：用整行矩形堆出来，保持硬边
func _px_circle(c: Vector2, r: float, col: Color, step: float = 4.0) -> void:
	var y := -r
	while y <= r:
		var half := sqrt(maxf(0.0, r * r - y * y))
		var hw := floorf(half / step) * step
		if hw > 0.0:
			draw_rect(Rect2(c.x - hw, c.y + y, hw * 2.0, step), col)
		y += step


func _draw_well() -> void:
	var c := Vector2(0, -65)
	if not _vis(c):
		return
	if _deco.has("well"):
		Depth.upright(self, c)
		_draw_deco("well", c + Vector2(0, 36), 1.0)
		Depth.flat(self)
		return
	_px_circle(c + Vector2(0, 8), 38.0, Color(0, 0, 0, 0.22))
	_px_circle(c, 32.0, Color("#6e6a62"))
	_px_circle(c, 26.0, Color("#8e8a80"))
	_px_circle(c, 18.0, Color("#2a4a6a"))
	_px_circle(c + Vector2(-4, -4), 8.0, Color("#4a7aa0"))
	draw_rect(Rect2(c.x - 34, c.y - 52, 6, 40), Color("#5a3f22"))
	draw_rect(Rect2(c.x + 28, c.y - 52, 6, 40), Color("#5a3f22"))
	draw_rect(Rect2(c.x - 42, c.y - 60, 84, 10), Color("#6b3a2a"))
	draw_rect(Rect2(c.x - 42, c.y - 60, 84, 3), Color("#8a5a3a"))


func _draw_decor() -> void:
	# 灯笼柱与树：沿着路和镇边
	var lamps := [Vector2(-110, -90), Vector2(110, -90), Vector2(-110, 460), Vector2(110, 460), Vector2(-260, -300), Vector2(260, -300), Vector2(-260, 200), Vector2(260, 200)]
	for l in lamps:
		if _vis(l):
			_draw_lamp(l)
	for i in 17:
		var p := Vector2(bounds.position.x + 30.0 + i * 108.0, bounds.position.y + 26.0 + float((i * 37) % 3) * 8.0)
		if _vis(p):
			_draw_tree(p, 1.0 + 0.2 * float(i % 3))
		var q := Vector2(bounds.position.x + 70.0 + i * 108.0, bounds.end.y - 24.0 - float((i * 53) % 3) * 8.0)
		if _vis(q):
			_draw_tree(q, 1.0 + 0.2 * float((i + 1) % 3))
	for j in 10:
		for sx in [bounds.position.x + 30.0, bounds.end.x - 30.0]:
			var p2 := Vector2(sx, bounds.position.y + 150.0 + j * 120.0)
			if _vis(p2):
				_draw_tree(p2, 1.1)


func _draw_lamp(at: Vector2) -> void:
	if _deco.has("lamp"):
		Depth.upright(self, at)
		var glow0 := 0.16 + 0.06 * sin(time * 3.0 + at.x)
		_px_circle(at + Vector2(0, -50), 26.0, Color("#ffb040", glow0))
		_draw_deco("lamp", at, 1.0)
		Depth.flat(self)
		return
	Depth.upright(self, at)
	draw_rect(Rect2(at.x - 3, at.y - 58, 6, 58), Color("#4a3320"))
	draw_rect(Rect2(at.x - 12, at.y - 62, 24, 8), Color("#3a2a18"))
	var glow := 0.18 + 0.06 * sin(time * 3.0 + at.x)
	_px_circle(at + Vector2(0, -34), 22.0, Color("#ffb040", glow))
	draw_rect(Rect2(at.x - 8, at.y - 50, 16, 20), Color("#c2452d"))
	draw_rect(Rect2(at.x - 8, at.y - 50, 16, 4), Color("#8a2a1a"))
	draw_rect(Rect2(at.x - 8, at.y - 34, 16, 4), Color("#8a2a1a"))
	draw_rect(Rect2(at.x - 4, at.y - 46, 5, 12), Color("#ffd070"))
	Depth.flat(self)


func _draw_tree(at: Vector2, s: float) -> void:
	if _deco.has("tree_a"):
		Depth.upright(self, at)
		var variants := ["tree_a", "tree_b", "tree_c"]
		var vid: String = variants[absi(int(at.x * 0.37 + at.y * 0.91)) % 3]
		_draw_deco(vid if _deco.has(vid) else "tree_a", at, s * 0.9)
		Depth.flat(self)
		return
	Depth.upright(self, at)
	_px_circle(at + Vector2(0, 4), 16.0 * s, Color(0, 0, 0, 0.2))
	draw_rect(Rect2(at.x - 5 * s, at.y - 22 * s, 10 * s, 26 * s), Color("#4a3320"))
	_px_circle(at + Vector2(0, -42 * s), 28.0 * s, Color("#2f5a2a"))
	_px_circle(at + Vector2(-8 * s, -50 * s), 20.0 * s, Color("#3f7a3a"))
	_px_circle(at + Vector2(10 * s, -38 * s), 14.0 * s, Color("#4f8a44"))
	_px_circle(at + Vector2(-12 * s, -56 * s), 8.0 * s, Color("#78b060"))
	Depth.flat(self)


func _draw_building(n: Dictionary) -> void:
	var bd: Dictionary = n["building"]
	var r := building_rect(n)
	if _draw_building_art(n, r):
		return
	if str(bd.get("kind", "")) == "stall":
		_draw_stall(n, r)
		return
	var wall := Color(str(bd["wall"]))
	var roof := Color(str(bd["roof"]))
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var roof_h := 52.0
	# 阴影
	draw_rect(Rect2(x + 8, y + h - 6, w, 14), Color(0, 0, 0, 0.2))
	# 墙：木板纹
	draw_rect(Rect2(x + 10, y + roof_h - 8, w - 20, h - roof_h + 8), wall)
	var plank := 0
	var px := x + 10.0
	while px < x + w - 10.0:
		draw_rect(Rect2(px, y + roof_h - 8, 2, h - roof_h + 8), wall.darkened(0.25))
		px += 14.0
		plank += 1
	draw_rect(Rect2(x + 10, y + h - 14, w - 20, 14), Color("#6e6a62"))         # 石基
	draw_rect(Rect2(x + 10, y + h - 14, w - 20, 3), Color("#8e8a80"))
	draw_rect(Rect2(x + 10, y + roof_h - 8, 6, h - roof_h + 8), wall.darkened(0.4))     # 立柱
	draw_rect(Rect2(x + w - 16, y + roof_h - 8, 6, h - roof_h + 8), wall.darkened(0.4))
	# 门
	var dw := 40.0
	var dh := 56.0
	var dx := x + w * 0.5 - dw * 0.5
	draw_rect(Rect2(dx - 4, y + h - 14 - dh - 4, dw + 8, dh + 4), Color("#3a2410"))
	draw_rect(Rect2(dx, y + h - 14 - dh, dw, dh), Color("#241608"))
	draw_rect(Rect2(dx + dw * 0.5 - 1, y + h - 14 - dh, 2, dh), Color("#3a2410"))
	# 窗（格子窗）
	for wx in [x + 28.0, x + w - 28.0 - 34.0]:
		draw_rect(Rect2(wx - 3, y + h - 70, 40, 34), Color("#3a2410"))
		draw_rect(Rect2(wx, y + h - 67, 34, 28), Color("#e8c880", 0.85))
		draw_rect(Rect2(wx + 16, y + h - 67, 2, 28), Color("#3a2410"))
		draw_rect(Rect2(wx, y + h - 55, 34, 2), Color("#3a2410"))
	# 屋顶：一层层梯形瓦片
	var rows := int(roof_h / 8.0)
	for i in rows:
		var inset := float(rows - 1 - i) * 6.0
		var col := roof if i % 2 == 0 else roof.darkened(0.18)
		draw_rect(Rect2(x - 12 + inset, y + i * 8, w + 24 - inset * 2.0, 8), col)
		draw_rect(Rect2(x - 12 + inset, y + i * 8 + 6, w + 24 - inset * 2.0, 2), roof.darkened(0.45))
	draw_rect(Rect2(x - 12 + 6.0 * float(rows - 1), y, w + 24 - 12.0 * float(rows - 1), 4), roof.lightened(0.3))     # 屋脊
	# 招牌
	var sign_rect := Rect2(x + w * 0.5 - 46.0, y + roof_h - 2.0, 92, 26)
	draw_rect(sign_rect.grow(3), Color("#2a1a08"))
	draw_rect(sign_rect, Color("#6b3a2a"))
	draw_string_outline(banner_font, sign_rect.position + Vector2(0, 20), str(bd["sign"]), HORIZONTAL_ALIGNMENT_CENTER, sign_rect.size.x, 20, 4, Color("#2a1a08"))
	draw_string(banner_font, sign_rect.position + Vector2(0, 20), str(bd["sign"]), HORIZONTAL_ALIGNMENT_CENTER, sign_rect.size.x, 20, Color("#f0c050"))


func _draw_stall(n: Dictionary, r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	draw_rect(Rect2(x + 6, y + r.size.y - 4, r.size.x, 12), Color(0, 0, 0, 0.2))
	# 遮阳伞（竹布条纹）
	for i in 8:
		draw_rect(Rect2(x - 8 + i * 17, y - 34, 17, 20), Color("#c2452d") if i % 2 == 0 else Color("#e8dcc0"))
	draw_rect(Rect2(x - 8, y - 16, 136, 4), Color("#8a2a1a"))
	draw_rect(Rect2(x + 2, y - 12, 4, r.size.y + 12), Color("#5a3f22"))
	draw_rect(Rect2(x + r.size.x - 6, y - 12, 4, r.size.y + 12), Color("#5a3f22"))
	# 桌子 + 书堆
	draw_rect(Rect2(x, y + 10, r.size.x, 20), Color("#7a5a3a"))
	draw_rect(Rect2(x, y + 10, r.size.x, 4), Color("#9a7a52"))
	for i in 4:
		draw_rect(Rect2(x + 10 + i * 26, y + 2, 20, 8), [Color("#3a5a8a"), Color("#8a3a2a"), Color("#d8c890"), Color("#3a6a4a")][i])
	draw_string_outline(banner_font, Vector2(x, y - 40), str((n["building"] as Dictionary)["sign"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, 4, Color("#2a1a08"))
	draw_string(banner_font, Vector2(x, y - 40), str((n["building"] as Dictionary)["sign"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color("#f0c050"))


func _draw_npc(n: Dictionary, near: bool) -> void:
	var pos: Vector2 = n["pos"]
	Depth.shadow(self, pos + Vector2(0, 1), 34.0)
	Depth.upright(self, pos)
	var kk := Depth.persp(pos.y)
	var tex: Texture2D = n["tex"]
	var top := pos.y - 62.0
	if tex != null:
		var sz := Vector2(float(n["tw"]), float(n["th"])) if n.has("tw") else tex.get_size()
		# 呼吸：以脚底为支点，身体极轻微地胀缩，NPC 才不会像贴在地上的纸片
		var breathe := 1.0 + 0.018 * sin(time * 2.2 + pos.x * 0.02)
		draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2((2.0 - breathe) * kk, breathe * kk / Depth.tilt))
		draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
		Depth.upright(self, pos)
		top = pos.y - sz.y - 8.0
	else:
		draw_rect(Rect2(pos.x - 10, pos.y - 44, 20, 44), Color("#8a6a45"))
	var label := str(n["name"])
	draw_string_outline(banner_font, Vector2(pos.x - 60, top), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, 4, Color(0, 0, 0, 0.85))
	draw_string(banner_font, Vector2(pos.x - 60, top), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color("#f3ead2"))
	if near:
		var bob2 := sin(time * 6.0) * 2.0
		var bp := Vector2(pos.x, top - 22.0 + bob2)
		draw_rect(Rect2(bp.x - 44, bp.y - 14, 88, 22), Color("#1c1812", 0.88))
		draw_rect(Rect2(bp.x - 44, bp.y - 14, 88, 22), Color("#c9a227"), false, 2.0)
		draw_string(banner_font, Vector2(bp.x - 44, bp.y + 3), "[E] 交谈", HORIZONTAL_ALIGNMENT_CENTER, 88, 14, Color("#f3ead2"))
	Depth.flat(self)


func _draw_player() -> void:
	var bob := Depth.bob(time, 2.0, 12.0) if moving else 0.0
	Depth.shadow(self, player_pos + Vector2(0, 3), 30.0, bob)
	if hero_art != null:
		# 村子专用素材：按朝向选 正面 / 背面 / 侧面；站着不动时停在第一帧
		var key := "hero_side"
		if absf(facing.y) > absf(facing.x):
			key = "hero_down" if facing.y > 0.0 else "hero_up"
		if hero_art.has(key):
			var lean := 0.06 * signf(facing.x) if (moving and key == "hero_side") else 0.0
			hero_art.draw(self, key, time if moving else 0.0, player_pos + Vector2(0, 4.0 - bob), facing.x < 0.0 and key == "hero_side", Color.WHITE, lean, 1.0 + (0.025 * sin(time * 24.0) if moving else 0.0))
			return
	if sprite_anim != null:
		if sprite_anim.draw(self, "walk" if moving else "idle", time, player_pos + Vector2(0, 14.0 - bob), facing.x < 0.0, Color.WHITE, Data.T("player_zoom")):
			return
	draw_circle(player_pos + Vector2(0, -14), 10.0, Color("#3aa6a0"))
