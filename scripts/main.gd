extends Node
## 主控：状态机、读取输入、驱动 GameWorld、相机跟随，以及登录 / 创建角色 / 排行榜 / 反馈的流程。
##
## 启动流程：
##   未配置在线服务（Net.api_url 为空）→ 桌面版单机；网页版提示"尚未配置"（没有游客模式）
##   已配置：有保存的登录 → 自动登录；否则登录 / 注册界面（注册必须有邀请码）
##           登录后以云端流派为准（云端没有而本机有，则上传）

enum State { BOOT, AUTH, CREATE, LOADOUT, PLAY, CHOOSE, PAUSED, END, MODAL }

var state: State = State.BOOT
var modal_return: State = State.LOADOUT
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
	hud.character_created.connect(_on_created)
	hud.recreate_requested.connect(_on_recreate)
	hud.auth_submitted.connect(_on_auth_submitted)
	hud.board_open_requested.connect(_open_board)
	hud.board_kind_requested.connect(_load_board)
	hud.feedback_open_requested.connect(_open_feedback)
	hud.feedback_submitted.connect(_on_feedback_submitted)
	hud.account_requested.connect(_on_account_requested)
	hud.modal_closed.connect(_close_modal)
	hud.meta_open_requested.connect(_open_meta)
	hud.meta_saved.connect(_on_meta_saved)
	world.player_died.connect(_on_end.bind(false))
	world.victory.connect(_on_end.bind(true))
	_show_game(false)
	_boot()


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
		State.CREATE:
			if event.is_action_pressed("ui_accept"):
				hud.confirm_create()
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
		State.MODAL:
			if event.is_action_pressed("ui_cancel"):
				_close_modal()
		State.END:
			if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
				get_tree().reload_current_scene()
			elif event is InputEventKey and event.pressed and event.keycode == KEY_B and Net.configured():
				_open_board()


## 创建角色 / 登录 / 开局选择时隐藏世界和 HUD，避免透出游戏画面
func _show_game(on: bool) -> void:
	world.visible = on
	hud.canvas.visible = on


# ---------------------------------------------------------------------
# 启动与登录
# ---------------------------------------------------------------------

func _boot() -> void:
	if not Net.configured():
		if Net.offline_allowed():
			_enter_character()          # 桌面版 / 本地调试：没配置在线服务时单机玩
			return
		state = State.BOOT
		hud.show_message("在线服务还没有配置好\n请联系管理员")
		return
	var last_nick := str(Save.session().get("nick", ""))
	if Save.has_session():
		state = State.BOOT
		hud.show_message("正在登录…")
		var r: Dictionary = await Net.resume()
		hud.hide_overlay()
		if bool(r.get("ok", false)):
			_after_login()
			return
	_enter_auth(last_nick)


func _enter_auth(prefill: String = "") -> void:
	state = State.AUTH
	_show_game(false)
	hud.show_auth(prefill)


func _on_auth_submitted(mode: String, nick: String, pin: String, code: String) -> void:
	if state != State.AUTH or hud.auth_busy:
		return
	hud.set_auth_busy(true)
	hud.set_auth_status("连接中…", false)
	var res: Dictionary
	if mode == "register":
		res = await Net.register(nick, pin, code)
	else:
		res = await Net.login(nick, pin)
	hud.set_auth_busy(false)
	if bool(res.get("ok", false)):
		hud.hide_auth()
		_after_login()
	else:
		hud.set_auth_status(str(res.get("msg", "出错了，请再试一次")), true)


## 登录成功：以云端流派为准；云端没有而本机有，则上传
func _after_login() -> void:
	Save.store_meta(Net.exp, Net.alloc)        # 修为 / 属性点以服务器为准
	if Net.school != "":
		Save.create_character(Net.school)
	elif Save.has_character():
		Net.save_state(Save.school())
	_enter_character()


func _on_account_requested() -> void:
	if state != State.LOADOUT:
		return
	hud.hide_loadout()
	if Net.logged_in():
		await Net.logout()
	_enter_auth("")


# ---------------------------------------------------------------------
# 角色与开局
# ---------------------------------------------------------------------

func _enter_character() -> void:
	if Save.has_character():
		_enter_loadout()
	else:
		_enter_create()


func _enter_create() -> void:
	state = State.CREATE
	_show_game(false)
	hud.show_create()


func _enter_loadout() -> void:
	state = State.LOADOUT
	_show_game(false)
	hud.show_loadout(Save.school())


## 创建角色：只在第一次（或重新创建时）出现，选定的流派写入存档（登录状态下同时存到云端）
func _on_created(school_id: String) -> void:
	if state != State.CREATE:
		return
	Save.create_character(school_id)
	if Net.logged_in():
		Net.save_state(school_id)
	hud.hide_create()
	_enter_loadout()


func _on_recreate() -> void:
	if state != State.LOADOUT:
		return
	Save.reset_character()
	if Net.logged_in():
		Net.save_state("")
	hud.hide_loadout()
	_enter_create()


func _on_loadout(starter_id: String, qinggong_id: String) -> void:
	if state != State.LOADOUT:
		return
	world.talent_stats = Meta.stats_for(Save.meta_alloc())
	world.start_run(starter_id, qinggong_id)
	hud.hide_loadout()
	_show_game(true)
	state = State.PLAY


# ---------------------------------------------------------------------
# 升级 / 秘籍
# ---------------------------------------------------------------------

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


# ---------------------------------------------------------------------
# 结算与成绩上传
# ---------------------------------------------------------------------

func _on_end(won: bool) -> void:
	state = State.END
	hud.hide_choices()
	hud.show_end(won)
	if not Net.configured():
		# 单机：本地直接结算修为
		if world.time >= 30.0:
			hud.set_end_extra(_exp_line(Save.add_run_exp(world.run_summary())))
		return
	if not Net.logged_in() or world.time < 30.0:
		return
	hud.set_end_extra("成绩上传中…")
	var res: Dictionary = await Net.submit_run(world.run_summary())
	if state != State.END:
		return
	if bool(res.get("ok", false)):
		Save.store_meta(Net.exp, Save.meta_alloc())
		var ranks: Dictionary = res.get("ranks", {})
		var line := "已上榜：总分榜第 %d 名" % int(ranks.get("score", 0))
		if bool(res.get("best", false)):
			line += "　（个人最高分！）"
		hud.set_end_extra(line + "\n" + _exp_line(res))
	else:
		hud.set_end_extra("成绩没能上传：%s" % str(res.get("msg", "未知错误")))


func _exp_line(r: Dictionary) -> String:
	var line := "修为 +%d　局外 Lv%d" % [int(r.get("gained", 0)), int(r.get("level", 1))]
	if bool(r.get("levelUp", false)):
		line += "　升级了！获得 3 个属性点、1 个天赋点"
	return line


# ---------------------------------------------------------------------
# 排行榜 / 反馈（弹层）
# ---------------------------------------------------------------------

func _open_modal() -> void:
	modal_return = state
	state = State.MODAL
	if modal_return == State.LOADOUT:
		hud.hide_loadout()
	else:
		hud.overlay.visible = false      # 从结算界面打开时，隐藏底下的结算文字，避免透出


func _open_board() -> void:
	if state != State.LOADOUT and state != State.END:
		return
	_open_modal()
	hud.show_board()
	_load_board(hud.board_kind)


func _load_board(kind: String) -> void:
	var res: Dictionary = await Net.board(kind, hud.board_group_only)
	hud.update_board(kind, res)


func _open_meta() -> void:
	if state != State.LOADOUT:
		return
	_open_modal()
	hud.show_meta()


func _on_meta_saved(alloc: Dictionary) -> void:
	if state != State.MODAL:
		return
	if Net.logged_in():
		hud.set_meta_status("保存中…", false)
		var res: Dictionary = await Net.save_alloc(alloc)
		if not bool(res.get("ok", false)):
			hud.set_meta_status(str(res.get("msg", "保存失败，请稍后再试")), true)
			return
	Save.set_meta_alloc(alloc)
	_close_modal()


func _open_feedback() -> void:
	if state != State.LOADOUT:
		return
	_open_modal()
	hud.show_feedback()


func _on_feedback_submitted(type: String, comment: String) -> void:
	hud.set_feedback_status("发送中…", false)
	var res: Dictionary = await Net.send_feedback(type, "开局界面", comment)
	if bool(res.get("ok", false)):
		hud.set_feedback_status("已收到，谢谢！", false)
		await get_tree().create_timer(1.0).timeout
		if state == State.MODAL:
			_close_modal()
	else:
		hud.set_feedback_status(str(res.get("msg", "发送失败，请稍后再试")), true)


func _close_modal() -> void:
	if state != State.MODAL:
		return
	hud.hide_board()
	hud.hide_feedback()
	hud.hide_meta()
	state = modal_return
	if modal_return == State.LOADOUT:
		_enter_loadout()
	else:
		hud.overlay.visible = true
