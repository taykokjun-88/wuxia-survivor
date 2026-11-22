class_name OrientationGuard
extends Node
## 手机 / 平板竖着拿：网页壳（export_presets.cfg 的 html/head_include，见 tools/web_head.html）会盖一层「请横屏游玩」，
## 并把 window.__wuxiaPortraitBlock 设为 true；这里读这个标志，竖屏时让游戏先停住（blocking = true）。
## 不在画布里画提示：竖屏时 canvas_items 拉伸后的画面只是一条很窄的横带，文字会小到看不清；用页面自己的 HTML 才清楚。
## 非网页环境（桌面 / 无头测试）永远不阻塞。

var blocking := false
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(dt: float) -> void:
	if not OS.has_feature("web"):
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.2
	blocking = bool(JavaScriptBridge.eval("window.__wuxiaPortraitBlock === true"))
