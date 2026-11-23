class_name Vfx
extends RefCounted
## 招式特效素材：读取 tools/process_vfx.py 生成的 assets/vfx/vfx.json 和横向条带 PNG。
## 约定：每个特效一条横向条带，N 帧、每帧 cell×cell；画面中心就是特效的原点；
## 带方向的特效（弹体 / 刀光 / 冲刺拖尾）朝右（+x），游戏里按角度旋转。
## 素材是黑底的高饱和发光图，处理时把亮度转成透明度，用普通 alpha 混合绘制（见 VfxLayer）。
## 没有素材的特效返回 has() == false，调用方继续用程序绘制的占位图。

var effects: Dictionary = {}   # id -> {tex, frames, fps, cell, loop}


func load_dir(dir: String) -> int:
	var path := dir + "/vfx.json"
	if not FileAccess.file_exists(path):
		return 0
	var json := JSON.new()
	if json.parse(FileAccess.open(path, FileAccess.READ).get_as_text()) != OK or not json.data is Dictionary:
		return 0
	var list: Dictionary = (json.data as Dictionary).get("effects", {})
	for id in list:
		var e: Dictionary = list[id]
		var tex_path := dir + "/" + str(e["file"])
		if ResourceLoader.exists(tex_path):
			add(str(id), load(tex_path), int(e["frames"]), float(e["fps"]), int(e["cell"]), bool(e.get("loop", false)), float(e.get("world_size", 0.0)), float(e.get("scale", 1.0)), float(e.get("forward", 0.0)))
	return effects.size()


## world_size：整张格子在游戏里的边长（像素）；0 表示由调用方按招式半径等决定
func add(id: String, tex: Texture2D, frames: int, fps: float, cell: int, loop: bool = false, world_size: float = 0.0, scale: float = 1.0, forward: float = 0.0) -> void:
	effects[id] = {"tex": tex, "frames": maxi(1, frames), "fps": fps, "cell": cell, "loop": loop, "world_size": world_size, "scale": scale, "forward": forward}


func has(id: String) -> bool:
	return effects.has(id)


## 循环特效按时间取帧；一次性特效按进度（0~1）铺满整个寿命
func frame_loop(id: String, time: float, offset: float = 0.0) -> int:
	var e: Dictionary = effects[id]
	return int(maxf(time + offset, 0.0) * float(e["fps"])) % int(e["frames"])


func frame_progress(id: String, progress: float) -> int:
	var e: Dictionary = effects[id]
	return clampi(int(progress * float(e["frames"])), 0, int(e["frames"]) - 1)


## 在 pos 处画第 frame 帧：size 是画面边长（世界像素），angle 是朝向（弧度）
func draw(ci: CanvasItem, id: String, frame: int, pos: Vector2, size: float, angle: float = 0.0, tint: Color = Color.WHITE, yscale: float = 1.0) -> void:
	var e: Dictionary = effects[id]
	var cell: int = e["cell"]
	var tex: Texture2D = e["tex"]
	ci.draw_set_transform(pos, angle, Vector2(1.0, yscale))
	ci.draw_texture_rect_region(tex, Rect2(-size * 0.5, -size * 0.5, size, size), Rect2(frame * cell, 0, cell, cell), tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
