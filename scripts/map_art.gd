class_name MapArt
extends RefCounted
## 地图美术：像素风地面瓦片 + 场景物件（树、石、旗、帐篷……），由 tools/process_art_grid.py 生成。
## 目录结构：<dir>/ground_0..N.png（64×64 瓦片）、<dir>/props/*.png + meta.json。
## 地面按低频噪声分成几种地貌；物件按格子哈希稳定地撒在地图上（只是装饰，不挡路）。
## 没有素材目录时 loaded == false，调用方画原来的占位背景。

const TILE := 64
const PROP_CELL := 340.0

var loaded := false
var ground: Array[Texture2D] = []
var ground_var: Array = []           # ground_var[i][o]：第 i 种地面的 8 种朝向（翻转 / 转 90°）
var props: Dictionary = {}          # id -> {tex, w, h}
var prop_weights: Dictionary = {}   # id -> 权重（0 表示不自动撒）
var seed_v := 1
var clear_radius := 230.0           # 出生点周围不放物件


func load_dir(dir: String, weights: Dictionary = {}) -> bool:
	loaded = false
	ground.clear()
	ground_var.clear()
	props.clear()
	for i in 8:
		var p := "%s/ground_%d.png" % [dir, i]
		if not ResourceLoader.exists(p):
			break
		var tex: Texture2D = load(p)
		ground.append(tex)
		var vars: Array = []
		for o in 8:
			var img: Image = tex.get_image()
			if (o & 4) != 0:
				img.rotate_90(CLOCKWISE)
			if (o & 1) != 0:
				img.flip_x()
			if (o & 2) != 0:
				img.flip_y()
			vars.append(ImageTexture.create_from_image(img))
		ground_var.append(vars)
	var meta_path := dir + "/props/meta.json"
	if FileAccess.file_exists(meta_path):
		var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if js is Dictionary:
			for id in js:
				var f := "%s/props/%s" % [dir, str(js[id]["file"])]
				if ResourceLoader.exists(f):
					props[str(id)] = {"tex": load(f), "w": int(js[id]["w"]), "h": int(js[id]["h"])}
	prop_weights = weights.duplicate()
	for id in props:
		if not prop_weights.has(id):
			prop_weights[id] = 1.0
	loaded = ground.size() >= 1
	return loaded


func _h(a: int, b: int, s: int = 0) -> int:
	return absi(((a * 73856093) ^ (b * 19349663) ^ ((s + seed_v) * 83492791)) % 2147483647)


func noise(x: float, y: float, s: int) -> float:
	return _vn(x, y, s)


func _vn(x: float, y: float, s: int) -> float:
	## 值噪声（0~1）：格点哈希 + 平滑插值
	var x0 := int(floorf(x))
	var y0 := int(floorf(y))
	var fx := x - x0
	var fy := y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := float(_h(x0, y0, s) % 1000) / 1000.0
	var b := float(_h(x0 + 1, y0, s) % 1000) / 1000.0
	var c := float(_h(x0, y0 + 1, s) % 1000) / 1000.0
	var d := float(_h(x0 + 1, y0 + 1, s) % 1000) / 1000.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## 某个瓦片用哪一种：0 泥地（基底）、1 枯草、2 灰烬、3 石板（少量）
func tile_index(cx: int, cy: int) -> int:
	if ground.size() == 1:
		return 0
	var x := float(cx)
	var y := float(cy)
	var stone := _vn(x * 0.11, y * 0.11, 31)
	if ground.size() > 3 and stone > 0.86:
		return 3
	var grass := _vn(x * 0.16, y * 0.16, 7)
	if ground.size() > 1 and grass > 0.7:
		return 1
	var ash := _vn(x * 0.2 + 40.0, y * 0.2, 19)
	if ground.size() > 2 and ash > 0.62:
		return 2
	return 0


func draw_ground(ci: CanvasItem, center: Vector2, half: Vector2) -> void:
	var x0 := int(floorf((center.x - half.x) / TILE))
	var x1 := int(floorf((center.x + half.x) / TILE))
	var y0 := int(floorf((center.y - half.y) / TILE))
	var y1 := int(floorf((center.y + half.y) / TILE))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			# 每块瓦片随机翻转 / 转 90°（8 种朝向），打散重复感
			var o := _h(cx, cy, 55) & 7
			ci.draw_texture_rect(ground_var[tile_index(cx, cy)][o], Rect2(cx * TILE, cy * TILE, TILE, TILE), false)


## 视野内的物件：[{id, pos}]，确定性（同一格子永远是同样的物件）
func visible_props(center: Vector2, half: Vector2) -> Array:
	var out: Array = []
	if props.is_empty():
		return out
	var ids: Array = []
	var total := 0.0
	for id in props:
		if float(prop_weights[id]) > 0.0:
			ids.append(id)
			total += float(prop_weights[id])
	var x0 := int(floorf((center.x - half.x - 120.0) / PROP_CELL))
	var x1 := int(floorf((center.x + half.x + 120.0) / PROP_CELL))
	var y0 := int(floorf((center.y - half.y - 160.0) / PROP_CELL))
	var y1 := int(floorf((center.y + half.y + 160.0) / PROP_CELL))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			for k in 2:
				var h := _h(cx, cy, 100 + k)
				if k == 0 and h % 100 >= 62:
					continue
				if k == 1 and h % 100 >= 22:
					continue
				var pos := Vector2(cx * PROP_CELL + float(_h(cx, cy, 200 + k) % int(PROP_CELL)), cy * PROP_CELL + float(_h(cx, cy, 300 + k) % int(PROP_CELL)))
				if pos.length() < clear_radius:
					continue
				var r := float(_h(cx, cy, 400 + k) % 1000) / 1000.0 * total
				var pick: String = ids[0]
				for id in ids:
					r -= float(prop_weights[id])
					if r < 0.0:
						pick = id
						break
				out.append({"id": pick, "pos": pos})
	return out


## 画一个物件：pos 是物件脚底中心；先画一个柔和的椭圆影子
func draw_prop(ci: CanvasItem, p: Dictionary) -> void:
	var d: Dictionary = props[p["id"]]
	var w: float = d["w"]
	var h: float = d["h"]
	var at: Vector2 = p["pos"]
	ci.draw_set_transform(at + Vector2(0, -2), 0.0, Vector2(1.0, 0.32))
	ci.draw_circle(Vector2.ZERO, w * 0.42, Color(0, 0, 0, 0.22))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_texture_rect(d["tex"], Rect2(at.x - w * 0.5, at.y - h + 4.0, w, h), false)
