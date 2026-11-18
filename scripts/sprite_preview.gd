class_name SpritePreview
extends Control
## 像素形象预览：放大 4 倍，循环播放几条代表性的动画（创建角色界面使用）。

const SEQUENCE := ["idle", "punch", "palm", "dash", "ult"]
const NAMES := {"idle": "待机", "punch": "出拳", "palm": "推掌", "dash": "轻功", "ult": "真气爆发"}
const SEGMENT := 1.4      # 每条动画播放的秒数
const ZOOM := 4.0

var anim: SpriteAnim = null
var clock := 0.0


func _init() -> void:
	clip_contents = true


func setup(school_id: String) -> void:
	anim = null
	clock = 0.0
	var dir := str(Data.schools[school_id].get("sprite_dir", ""))
	if dir != "":
		var a := SpriteAnim.new()
		if a.load_dir(dir):
			anim = a
	queue_redraw()


func _process(dt: float) -> void:
	clock += dt
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.10, 0.13, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#c9a227", 0.6), false, 2.0)
	if anim == null:
		draw_string(font, Vector2(0, size.y * 0.5), "暂无像素形象", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color("#cfc6ae"))
		return
	var name: String = SEQUENCE[int(clock / SEGMENT) % SEQUENCE.size()]
	var t := fmod(clock, SEGMENT)
	var ground := size.y - 46.0
	draw_line(Vector2(size.x * 0.2, ground + 4.0), Vector2(size.x * 0.8, ground + 4.0), Color(1, 1, 1, 0.12), 2.0)
	anim.draw(self, name, t, Vector2(size.x * 0.5, ground), false, Color.WHITE, ZOOM)
	draw_string(font, Vector2(0, size.y - 14.0), "像素形象 · %s" % NAMES[name], HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color("#cfc6ae"))
