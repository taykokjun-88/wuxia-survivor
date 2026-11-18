extends Node
## 主控：状态机（菜单 / 游戏 / 升级选择 / 暂停 / 结算）、读取输入、驱动 GameWorld、相机跟随。

enum State { MENU, PLAY, LEVELUP, PAUSED, END }

var state: State = State.MENU
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
	world.player_died.connect(_on_end.bind(false))
	world.victory.connect(_on_end.bind(true))
	hud.show_menu()


func _physics_process(dt: float) -> void:
	if state != State.PLAY:
		return
	world.input_move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash"):
		world.input_dash = true
	if Input.is_action_just_pressed("ult"):
		world.input_ult = true
	world.step(dt)
	if not world.over and world.pending_levels > 0:
		_open_levelup()


func _process(_dt: float) -> void:
	cam.position = world.player_pos
	if world.shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * world.shake
	else:
		cam.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.MENU:
			if event.is_action_pressed("ui_accept"):
				state = State.PLAY
				hud.hide_overlay()
		State.PLAY:
			if event.is_action_pressed("ui_cancel"):
				state = State.PAUSED
				hud.show_pause()
		State.PAUSED:
			if event.is_action_pressed("ui_cancel"):
				state = State.PLAY
				hud.hide_overlay()
		State.LEVELUP:
			if event is InputEventKey and event.pressed and not event.echo:
				var idx := int(event.keycode) - int(KEY_1)
				if idx >= 0 and idx < 3:
					_on_choice(idx)
		State.END:
			if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
				get_tree().reload_current_scene()


func _open_levelup() -> void:
	state = State.LEVELUP
	choices = world.roll_choices()
	hud.show_choices(choices)


func _on_choice(i: int) -> void:
	if state != State.LEVELUP or i >= choices.size():
		return
	world.apply_choice(choices[i])
	hud.hide_choices()
	if world.pending_levels > 0:
		_open_levelup()
	else:
		state = State.PLAY


func _on_end(won: bool) -> void:
	state = State.END
	hud.hide_choices()
	hud.show_end(won)
