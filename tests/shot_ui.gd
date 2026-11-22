extends Node
## 界面截图：出发前界面 / 升级选卡 / 刀客 HUD。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_ui.tscn

const DT := 1.0 / 60.0
var main: Node
var w: GameWorld
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	w = main.world
	await _frames(2)
	Save.create_character("blade")
	main._enter_town()
	await _frames(2)
	main.state = main.State.LOADOUT
	main.hud.show_loadout("blade", "black_wind")
	await _frames(3)
	await _snap("ui1_loadout")
	main.hud.hide_loadout() if main.hud.has_method("hide_loadout") else null
	main._show_game(true)
	w.start_run("wuhu_blade", "tashue", "black_wind", {})
	w.add_skill("xuedao")
	w.add_skill("tulong_art")
	w.xinfa = {"changsheng": 2}
	w.xinfa_q = {"changsheng": [1]}
	w.recalc()
	w.soul = 62.0
	for i in 30:
		w.step(DT)
	await _frames(2)
	await _snap("ui2_blade_hud")
	w.soul = 100.0
	await _frames(2)
	await _snap("ui3_blade_hud_full")
	var ch: Array = w.roll_choices(3)
	ch[0] = {"kind": "up_skill", "id": "xuedao", "dir": "damage", "tier": 3, "src": "level", "tag": "传说", "color": "#f0c050", "title": "朱砂饮锋刀 · 加强伤害", "desc": "伤害 +40%　（已升级 3/10）"}
	ch[1] = {"kind": "new_xinfa", "id": "chunyang", "src": "level", "tag": "心法", "title": "修习：煌日真诀【阳】", "desc": Data.xinfa["chunyang"]["desc"]}
	ch[2] = {"kind": "up_xinfa", "id": "changsheng", "tier": 2, "src": "level", "tag": "优秀", "color": "#b070e8", "title": "玄龟吐纳 · 强化（Lv2→3）", "desc": "同修招式与被动属性 +3 份强度（累计 2 → 5 份）　（已强化 1/3）"}
	main.hud.show_choices(ch, "升级！选择一项")
	await _frames(3)
	await _snap("ui4_choices")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
