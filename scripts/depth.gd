class_name Depth
extends RefCounted
## 立体感小工具：脚下接触影子、走路起伏、倾斜 / 挤压。目的是让像素角色不像「贴在地上的纸片」。


static var _shadow_tex: Texture2D = null
## 伪 2.5D 的俯视倾角：世界节点在竖直方向压缩 tilt 倍（地面、圈、预警变成椭圆，像从斜上方看）；
## 站立的东西（角色 / 怪物 / 场景物件 / 文字）要反向拉伸 1/tilt 才不会变扁。1.0 = 不倾斜（村子、测试里用）
static var tilt := 1.0


## 让后面的绘制「站直」：以 anchor_y 这一行为不动点，竖直拉伸 1/tilt；画完用 flat() 还原
static func upright(ci: CanvasItem, anchor_y: float) -> void:
	if tilt < 0.999:
		ci.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0 / tilt), Vector2(0.0, anchor_y * (1.0 - 1.0 / tilt))))


static func flat(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 柔边的椭圆影子贴图（只建一次）：一次 draw_texture_rect 代替三个圆 + 两次变换，同屏几百个怪时省很多
static func shadow_texture() -> Texture2D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.2), Color(0, 0, 0, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_shadow_tex = t
	return _shadow_tex


## 脚下的接触影子；lift 是角色离地的高度（跳起 / 起伏时影子变小变淡）
static func shadow(ci: CanvasItem, foot: Vector2, width: float, lift: float = 0.0) -> void:
	var k := clampf(1.0 - lift * 0.05, 0.6, 1.0)
	var rw := width * 0.66 * k
	ci.draw_texture_rect(shadow_texture(), Rect2(foot.x - rw, foot.y - rw * 0.3, rw * 2.0, rw * 0.6), false, Color(1, 1, 1, k))


## 走路的上下起伏：每一步脚落地时最低
static func bob(t: float, amp: float, speed: float, phase: float = 0.0) -> float:
	return absf(sin(t * speed + phase)) * amp


## 挤压 / 拉伸：squash < 1 时变扁变宽，> 1 时变高变窄（体积大致守恒）
static func scale_of(squash: float, flip: bool = false, zoom: float = 1.0) -> Vector2:
	return Vector2((-1.0 if flip else 1.0) * (2.0 - squash) * zoom, squash * zoom / tilt)
