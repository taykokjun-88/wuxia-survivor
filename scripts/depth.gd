class_name Depth
extends RefCounted
## 立体感小工具：脚下接触影子、走路起伏、倾斜 / 挤压。目的是让像素角色不像「贴在地上的纸片」。


## 脚下的接触影子：外圈柔、内圈实；lift 是角色离地的高度（跳起 / 起伏时影子变小变淡）
static func shadow(ci: CanvasItem, foot: Vector2, width: float, lift: float = 0.0) -> void:
	var k := clampf(1.0 - lift * 0.05, 0.6, 1.0)
	ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.3))
	ci.draw_circle(Vector2.ZERO, width * 0.62 * k, Color(0, 0, 0, 0.12 * k))
	ci.draw_circle(Vector2.ZERO, width * 0.46 * k, Color(0, 0, 0, 0.18 * k))
	ci.draw_circle(Vector2.ZERO, width * 0.28 * k, Color(0, 0, 0, 0.22 * k))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 走路的上下起伏：每一步脚落地时最低
static func bob(t: float, amp: float, speed: float, phase: float = 0.0) -> float:
	return absf(sin(t * speed + phase)) * amp


## 挤压 / 拉伸：squash < 1 时变扁变宽，> 1 时变高变窄（体积大致守恒）
static func scale_of(squash: float, flip: bool = false, zoom: float = 1.0) -> Vector2:
	return Vector2((-1.0 if flip else 1.0) * (2.0 - squash) * zoom, squash * zoom)
