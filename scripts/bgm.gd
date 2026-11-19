extends Node
## 背景音乐（Autoload: Bgm）：两个播放器交叉淡入淡出，曲目放在 assets/bgm/<名字>.ogg 并循环。
## 登录 = login，小镇 = town，关卡 = 地图 id（黑风寨 black_wind），小 Boss = boss，大 Boss = final_boss。
## 没有对应文件的曲目静音；无头模式（测试）不出声。开关记在本地存档 ui.bgm_off。

const FADE := 1.4
const VOLUME_DB := -10.0

var enabled := true
var current := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _streams: Dictionary = {}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui: Variant = Save.data.get("ui", {})
	if ui is Dictionary and bool((ui as Dictionary).get("bgm_off", false)):
		enabled = false
	_setup_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)


func _setup_bus() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")


func _stream_of(id: String) -> AudioStream:
	if not _streams.has(id):
		var path := "res://assets/bgm/%s.ogg" % id
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_streams[id] = s
	return _streams[id]


## 切换到曲目 id（空串 = 淡出停止）。同一首正在播就什么也不做
func play(id: String) -> void:
	if _players.is_empty() or id == current:
		return
	current = id
	if not enabled:
		return
	_crossfade(id)


func _crossfade(id: String) -> void:
	var old := _players[_active]
	var s := _stream_of(id) if id != "" else null
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -60.0, FADE)
	tw.chain().tween_callback(old.stop)
	if s != null:
		_active = 1 - _active
		var nw := _players[_active]
		nw.stream = s
		nw.volume_db = -60.0
		nw.play()
		var tw2 := create_tween()
		tw2.tween_property(nw, "volume_db", VOLUME_DB, FADE)


func stop(_fade: float = FADE) -> void:
	play("")


func set_enabled(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	enabled = on
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	(ui as Dictionary)["bgm_off"] = not on
	Save.data["ui"] = ui
	Save.save_data()
	if on:
		var want := current
		current = ""
		play(want)
	else:
		for p in _players:
			p.stop()
