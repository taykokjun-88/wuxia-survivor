class_name VfxLayer
extends Node2D
## 招式特效层：画在世界上面。画的是弹体、刀光 / 冲击 / 光环、命中火花和区域特效（有素材的才画）。
## 用普通的 alpha 混合（不是叠加）：游戏背景是浅色宣纸，叠加会把特效冲成一片白。透明度来自素材的亮度（见 process_vfx.py）。
## 没有素材的特效仍由 GameWorld 自己用线条和圆弧画。

const PROJ_IDS := {"wave": "proj_wave", "bolt": "proj_bolt", "palm": "proj_palm", "finger": "proj_finger"}
const HOSTILE_IDS := {"claw": "boss_claw_proj", "palm": "boss_dark_palm", "blade": "boss_blade_proj"}      # Boss 弹体的特效素材（有才画）
const EMP_RING := Color("#4fe0d0")

var world: GameWorld


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5


func _process(_dt: float) -> void:
	if visible and world != null and world.vfx != null and not world.vfx.effects.is_empty():
		queue_redraw()


func _draw() -> void:
	if world == null or world.vfx == null or world.vfx.effects.is_empty():
		return
	var v := world.vfx
	var t := world.time
	# 区域（裂地 / 旋涡）：循环
	for z in world.zones:
		var id := "zone_crack" if z["kind"] == "crack" else ("zone_vortex" if z["kind"] == "vortex" else "")
		if id != "" and v.has(id):
			var a := 1.0 - float(z["t"]) / float(z["life"])
			v.draw(self, id, v.frame_loop(id, t), z["pos"], float(z["r"]) * 2.2, 0.0, Color(1, 1, 1, clampf(a * 2.0, 0.0, 1.0)))
	# 弹体：循环，朝向飞行方向；催动版偏青并略大
	for p in world.projs:
		var pid: String = str(HOSTILE_IDS.get(p.kind, "")) if p.hostile else str(PROJ_IDS.get(p.kind, ""))
		if pid == "":
			continue
		if not v.has(pid) or not world._vis(p.pos):
			continue
		var ws := float(v.effects[pid]["world_size"])
		var size := (ws if ws > 0.0 else maxf(p.radius * 3.2, 34.0)) * (1.25 if p.empowered else 1.0)
		if p.empowered:    # 催动版：保持原色，加一圈青色光环
			draw_arc(p.pos, size * 0.3, 0.0, TAU, 24, Color(EMP_RING, 0.85), 3.0)
			draw_arc(p.pos, size * 0.3 + 5.0, 0.0, TAU, 24, Color(EMP_RING, 0.3), 5.0)
		v.draw(self, pid, v.frame_loop(pid, t, float(p.skill_id.length()) * 0.07), p.pos, size, p.angle)
	# 一次性特效：按寿命铺满全部帧
	for fx in world.effects:
		var id2 := str(fx.get("vfx", ""))
		if id2 == "" or not v.has(id2):
			continue
		var prog := float(fx["t"]) / float(fx["life"])
		var sz := float(fx.get("size", 0.0))
		if sz <= 0.0 and float(v.effects[id2]["world_size"]) > 0.0:
			sz = float(v.effects[id2]["world_size"])
		if sz <= 0.0:
			sz = float(fx["r1"]) * 2.0 if fx.has("r1") else (float(fx["r"]) * 2.2 if fx.has("r") else 64.0)
		var col: Color = fx.get("tint", Color.WHITE)
		sz *= float(v.effects[id2]["scale"])
		var ang := float(fx.get("angle", 0.0))
		var at: Vector2 = fx["pos"] + Vector2.from_angle(ang) * sz * float(v.effects[id2]["forward"])
		v.draw(self, id2, v.frame_progress(id2, prog), at, sz, ang, col)
