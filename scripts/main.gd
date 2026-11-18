extends Node
## 主控：状态机（开局选择 / 游戏 / 升级与秘籍选择 / 暂停 / 结算）、读取输入、驱动 GameWorld、相机跟随。

enum State { LOADOUT, PLAY, CHOOSE, PAUSED, END }

var state: State = State.LOADOUT
var world: GameWorld
var cam: Camera2D
var hud: GameHud
var choices: Array = []


func _ready() -> void:
	world = GameWorld.new()
	add_child(world)
	cam = Camera2D.new()
	add_child(cam)
	hud = GameHud.new()
	add_child(hud)
	hud.setup(world)
	hud.choice_selected.connect(_on_choice)
	hud.loadout_confirmed.connect(_on_loadout)
	world.player_died.connect(_on_end.bind(false))
	world.victory.connect(_on_end.bind(true))
	hud.show_loadout()


func _physics_process(dt: float) -> void:
	if state != State.PLAY:
		return
	world.input_move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash"):
		world.input_dash = true
	if Input.is_action_just_pressed("ult"):
		world.input_ult = true
	world.step(dt)
	if not world.over:
		_check_pending()


func _process(_dt: float) -> void:
	cam.position = world.player_pos
	if world.shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * world.shake
	else:
		cam.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.LOADOUT:
			if event.is_action_pressed("ui_accept"):
				hud.confirm_loadout()
		State.PLAY:
			if event.is_action_pressed("ui_cancel"):
				state = State.PAUSED
				hud.show_pause()
		State.PAUSED:
			if event.is_action_pressed("ui_cancel"):
				state = State.PLAY
				hud.hide_overlay()
		State.CHOOSE:
			if event is InputEventKey and event.pressed and not event.echo:
				var idx := int(event.keycode) - int(KEY_1)
				if idx >= 0 and idx < 3:
					_on_choice(idx)
		State.END:
			if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
				get_tree().reload_current_scene()


func _on_loadout(starter_id: String, qinggong_id: String) -> void:
	if state != State.LOADOUT:
		return
	world.start_run(starter_id, qinggong_id)
	hud.hide_loadout()
	state = State.PLAY


## 秘籍（小 Boss 掉落）优先于普通升级
func _check_pending() -> void:
	if world.pending_chests > 0:
		choices = world.roll_chest_choices()
		hud.show_choices(choices, "击败小 Boss，获得秘籍！选择本局的专属强化（按 1 / 2 / 3 或点击）")
		state = State.CHOOSE
	elif world.pending_levels > 0:
		choices = world.roll_choices()
		hud.show_choices(choices, "突破！选择一项领悟（按 1 / 2 / 3 或点击）")
		state = State.CHOOSE


func _on_choice(i: int) -> void:
	if state != State.CHOOSE or i >= choices.size():
		return
	world.apply_choice(choices[i])
	hud.hide_choices()
	state = State.PLAY
	_check_pending()


func _on_end(won: bool) -> void:
	state = State.END
	hud.hide_choices()
	hud.show_end(won)
