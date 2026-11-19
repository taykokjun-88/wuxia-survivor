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
			add(str(id), load(f), int(d["frames"]), float(d["fps"]), int(d["w"]), int(d["h"]))
	return sprites.size()


func add(id: String, tex: Texture2D, frames: int, fps: float, w: int, h: int) -> void:
	# 预先生成水平翻转的整条（帧顺序也反过来）：怪物很多时用它直接绘制，不需要逐个设置变换
	var tex_f: Texture2D = null
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.flip_x()
		tex_f = ImageTexture.create_from_image(img)
	sprites[id] = {"tex": tex, "tex_f": tex_f, "frames": maxi(1, frames), "fps": fps, "w": w, "h": h}


func has(id: String) -> bool:
	return sprites.has(id)


func height_of(id: String) -> float:
	return float(sprites[id]["h"])


## 快速绘制（同屏怪物很多时用）：不做倾斜 / 挤压，没有变换，一次绘制调用
func draw_fast(ci: CanvasItem, id: String, t: float, feet: Vector2, flip: bool, tint: Color = Color.WHITE) -> void:
	var d: Dictionary = sprites[id]
	var w: int = d["w"]
	var h: int = d["h"]
	var frames: int = d["frames"]
	var f := int(maxf(t, 0.0) * float(d["fps"])) % frames
	var tex: Texture2D = d["tex"]
	if flip and d["tex_f"] != null:
		tex = d["tex_f"]
		f = frames - 1 - f
	ci.draw_texture_rect_region(tex, Rect2(feet.x - w * 0.5, feet.y - h, w, h), Rect2(f * w, 0, w, h), tint)


## feet：脚底中心（世界坐标）；flip：朝左
func draw(ci: CanvasItem, id: String, t: float, feet: Vector2, flip: bool, tint: Color = Color.WHITE, rot: float = 0.0, squash: float = 1.0) -> void:
	var d: Dictionary = sprites[id]
	var w: int = d["w"]
	var h: int = d["h"]
	var f := int(maxf(t, 0.0) * float(d["fps"])) % int(d["frames"])
	var tex: Texture2D = d["tex"]
	ci.draw_set_transform(feet, rot, Depth.scale_of(squash, flip))
	ci.draw_texture_rect_region(tex, Rect2(-w * 0.5, -h, w, h), Rect2(f * w, 0, w, h), tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
