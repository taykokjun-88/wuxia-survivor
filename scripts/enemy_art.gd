class_name EnemyArt
extends RefCounted
## 怪物像素立绘：横向条带（N 帧行走循环，朝右），由 tools/process_art_grid.py 的 enemy 模式生成。
## 条带里脚底对齐在格子底边。键：bandit / blade / soldier（按敌人类型），elite（任何精英），boss（最终 Boss）。
## 没有素材的怪物（如小 Boss）返回 has() == false，由 GameWorld 画占位图形。

var sprites: Dictionary = {}   # id -> {tex, frames, fps, w, h}


func load_dir(dir: String) -> int:
	var path := dir + "/meta.json"
	if not FileAccess.file_exists(path):
		return 0
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not js is Dictionary:
		return 0
	for id in js:
		var d: Dictionary = js[id]
		var f := "%s/%s" % [dir, str(d["file"])]
		if ResourceLoader.exists(f):
			add(str(id), load(f), int(d["frames"]), float(d["fps"]), int(d["w"]), int(d["h"]), float(d.get("scale", 1.0)))
	return sprites.size()


func add(id: String, tex: Texture2D, frames: int, fps: float, w: int, h: int, scale: float = 1.0) -> void:
	# 预先生成水平翻转的整条（帧顺序也反过来）：怪物很多时用它直接绘制，不需要逐个设置变换
	var tex_f: Texture2D = null
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.flip_x()
		tex_f = ImageTexture.create_from_image(img)
	sprites[id] = {"tex": tex, "tex_f": tex_f, "frames": maxi(1, frames), "fps": fps, "w": w, "h": h, "scale": scale}


func has(id: String) -> bool:
	return sprites.has(id)


func height_of(id: String) -> float:
	return float(sprites[id]["h"]) * float(sprites[id].get("scale", 1.0))


## 快速绘制（同屏怪物很多时用）：不做倾斜 / 挤压，没有变换，一次绘制调用
func draw_fast(ci: CanvasItem, id: String, t: float, feet: Vector2, flip: bool, tint: Color = Color.WHITE, fr0: int = 0, fr1: int = -1) -> void:
	var d: Dictionary = sprites[id]
	var w: int = d["w"]
	var h: int = d["h"]
	var frames: int = d["frames"]
	var last := frames - 1 if fr1 < 0 else mini(fr1, frames - 1)
	var f := fr0 + int(maxf(t, 0.0) * float(d["fps"])) % (last - fr0 + 1)       # 只在 fr0~fr1 帧里循环（弓手：行走 0~1 / 拉弓 2~3）
	var tex: Texture2D = d["tex"]
	var sc: float = float(d.get("scale", 1.0))
	if flip and d["tex_f"] != null:
		tex = d["tex_f"]
		f = frames - 1 - f
	ci.draw_texture_rect_region(tex, Rect2(feet.x - w * sc * 0.5, feet.y - h * sc, w * sc, h * sc), Rect2(f * w, 0, w, h), tint)


## feet：脚底中心（世界坐标）；flip：朝左
func draw(ci: CanvasItem, id: String, t: float, feet: Vector2, flip: bool, tint: Color = Color.WHITE, rot: float = 0.0, squash: float = 1.0, fr0: int = 0, fr1: int = -1) -> void:
	var d: Dictionary = sprites[id]
	var w: int = d["w"]
	var h: int = d["h"]
	var last := int(d["frames"]) - 1 if fr1 < 0 else mini(fr1, int(d["frames"]) - 1)
	var f := fr0 + int(maxf(t, 0.0) * float(d["fps"])) % (last - fr0 + 1)
	var tex: Texture2D = d["tex"]
	var sc: float = float(d.get("scale", 1.0))
	ci.draw_set_transform(feet, rot, Depth.scale_of(squash, flip, 1.0, feet.y))
	ci.draw_texture_rect_region(tex, Rect2(-w * sc * 0.5, -h * sc, w * sc, h * sc), Rect2(f * w, 0, w, h), tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
