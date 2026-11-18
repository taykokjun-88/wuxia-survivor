class_name SpriteAnim
extends RefCounted
## 角色动画：读取 tools/process_sprites.py 生成的 anim.json 和横向条带 PNG，按动画名与时间取帧。
## 缺少的动画回退到 idle；idle 也没有时 draw() 返回 false，调用方改画占位图形。

const FALLBACK := {
	"walk": "idle", "dash": "walk", "hurt": "idle", "punch": "idle",
	"palm": "punch", "ult": "palm", "death": "hurt",
}

var cell := 64
var anims: Dictionary = {}   # name -> {tex, frames, fps, loop}


func load_dir(dir: String) -> bool:
	var path := dir + "/anim.json"
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.open(path, FileAccess.READ).get_as_text()) != OK or not json.data is Dictionary:
		return false
	var d: Dictionary = json.data
	cell = int(d.get("cell", 64))
	var list: Dictionary = d.get("anims", {})
	for name in list:
		var a: Dictionary = list[name]
		var tex_path := dir + "/" + str(a["file"])
		if ResourceLoader.exists(tex_path):
			add_anim(str(name), load(tex_path), int(a["frames"]), float(a["fps"]), bool(a.get("loop", true)))
	return anims.has("idle")


func add_anim(name: String, tex: Texture2D, frames: int, fps: float, loop: bool = true) -> void:
	anims[name] = {"tex": tex, "frames": frames, "fps": fps, "loop": loop}


## 实际会播放的动画名（逐级回退到 idle）；没有可用动画时返回 ""
func resolve(name: String) -> String:
	var n := name
	for i in 6:
		if anims.has(n):
			return n
		if not FALLBACK.has(n):
			break
		n = str(FALLBACK[n])
	return "idle" if anims.has("idle") else ""


func frame_index(name: String, t: float) -> int:
	var a: Dictionary = anims[name]
	var frames: int = a["frames"]
	var i := int(maxf(t, 0.0) * float(a["fps"]))
	return i % frames if bool(a["loop"]) else mini(i, frames - 1)


func anim_length(name: String) -> float:
	var key := resolve(name)
	if key == "":
		return 0.0
	var a: Dictionary = anims[key]
	return float(a["frames"]) / float(a["fps"])


## foot：脚底中心（世界坐标）；flip：水平翻转（面朝左）
func draw(ci: CanvasItem, name: String, t: float, foot: Vector2, flip: bool, tint: Color = Color.WHITE) -> bool:
	var key := resolve(name)
	if key == "":
		return false
	var a: Dictionary = anims[key]
	var tex: Texture2D = a["tex"]
	var src := Rect2(frame_index(key, t) * cell, 0, cell, cell)
	# 条带里角色脚底距格子底部 4px
	ci.draw_set_transform(Vector2(foot.x, foot.y + 4.0 - cell), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(tex, Rect2(-cell * 0.5, 0, cell, cell), src, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
