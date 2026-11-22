extends Node
## 主控：状态机、读取输入、驱动 GameWorld、相机跟随，以及登录 / 创建角色 / 排行榜 / 反馈的流程。
##
## 启动流程：
##   未配置在线服务（Net.api_url 为空）→ 桌面版单机；网页版提示"尚未配置"（没有游客模式）
##   已配置：有保存的登录 → 自动登录；否则登录 / 注册界面（注册必须有邀请码）
##           登录后以云端流派为准（云端没有而本机有，则上传）

enum State { BOOT, AUTH, CHARS, CREATE, TOWN, DIALOG, LOADOUT, PLAY, CHOOSE, PAUSED, END, MODAL }

var state: State = State.BOOT
var modal_return: State = State.TOWN
var current_map := "black_wind"
var stage_bgm := "black_wind"       # 当前关卡的曲子（没有专属曲目就用黑风寨的）
var dialog_actions: Array = []
var dialog_npc: Dictionary = {}
var town: Town
var world: GameWorld
var cam: Camera2D
var touch: TouchControls
var guard: OrientationGuard
var hud: GameHud
var choices: Array = []
var choice_title := ""
var choice_is_chest := false


func _ready() -> void:
	world = GameWorld.new()
	add_child(world)
	town = Town.new()
	add_child(town)
	town.visible = false
	cam = Camera2D.new()
	add_child(cam)
	hud = GameHud.new()
	add_child(hud)
	touch = TouchControls.new()
	add_child(touch)
	touch.world = world
	touch.town = town
	touch.pause_pressed.connect(_touch_pause)
	touch.detail_pressed.connect(func() -> void: hud.toggle_hud())
	touch.interact_pressed.connect(_touch_interact)
	touch.menu_pressed.connect(func() -> void:
		if state == State.TOWN:
			_open_town_menu())
	guard = OrientationGuard.new()
	add_child(guard)
	hud.end_continue_requested.connect(func() -> void:
		if state == State.END and not _uploading:
			_end_to_town())
	hud.setup(world)
	hud.choice_selected.connect(_on_choice)
	hud.reroll_requested.connect(_on_reroll)
	hud.loadout_confirmed.connect(_on_loadout)
	hud.character_created.connect(_on_created)
	hud.char_chosen.connect(_on_char_chosen)
	hud.char_create_requested.connect(_on_char_create_requested)
	hud.char_delete_requested.connect(_on_char_delete)
	hud.chars_back_requested.connect(_on_account_requested)
	hud.create_back_requested.connect(_enter_character)
	hud.auth_submitted.connect(_on_auth_submitted)
	hud.board_open_requested.connect(_open_board)
	hud.board_kind_requested.connect(_load_board)
	hud.feedback_open_requested.connect(_open_feedback)
	hud.feedback_submitted.connect(_on_feedback_submitted)
	hud.account_requested.connect(_on_account_requested)
	hud.modal_closed.connect(_close_modal)
	hud.dialog_option.connect(_on_dialog_option)
	hud.loadout_cancelled.connect(_on_loadout_cancel)
	hud.pause_resume.connect(_on_pause_resume)
	hud.pause_abandon.connect(_on_pause_abandon)
	hud.meta_open_requested.connect(_open_meta)
	hud.meta_saved.connect(_on_meta_saved)
	hud.talents_open_requested.connect(_open_talents)
	hud.talents_saved.connect(_on_talents_saved)
	hud.gear_open_requested.connect(_open_gear)
	hud.gear_saved.connect(_on_gear_saved)
	hud.enhance_requested.connect(_on_enhance)
	world.player_died.connect(_on_end.bind(false))
	world.victory.connect(_on_end.bind(true))
	_show_game(false)
	_boot()


func _touch_pause() -> void:
	if state == State.PLAY:
		state = State.PAUSED
		hud.show_pause()


func _touch_interact() -> void:
	if state == State.TOWN:
		var npc := town.near_npc()
		if not npc.is_empty():
			_talk(npc)


func _physics_process(dt: float) -> void:
	if guard != null and guard.blocking:         # 手机竖屏：盖着「请横屏」提示，游戏先停住
		return
	if state == State.TOWN:
		town.input_move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		town.step(dt)
		return
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


## 当前场景该放哪首曲子：登录 / 小镇 / 关卡（有 Boss 在场时换 Boss 曲）；结算时淡出
func _desired_bgm() -> String:
	match state:
		State.BOOT, State.AUTH, State.CHARS, State.CREATE:
			return "login"
		State.TOWN, State.DIALOG, State.LOADOUT:
			return "town"
		State.MODAL:
			return "town" if modal_return != State.END else ""
		State.END:
			return ""
	var mini := false
	for b in world.bosses:
		if b.alive:
			if b.is_final:
				return "final_boss"
			mini = true
	if mini:
		return "boss"
	return stage_bgm


func _process(_dt: float) -> void:
	Bgm.play(_desired_bgm())
	touch.set_mode("play" if state == State.PLAY else ("town" if state == State.TOWN else ""))
	GameHud.touch_mode = touch.is_active() or (touch.touch_seen and not touch.keyboard_seen)
	if town.visible:
		cam.position = Vector2(town.player_pos.x, town.player_pos.y * Depth.tilt)
		Depth.cam_y = town.player_pos.y
		cam.offset = Vector2.ZERO
		return
	Depth.cam_y = world.player_pos.y
	cam.position = Vector2(world.player_pos.x, world.player_pos.y * Depth.tilt)
	if world.shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * world.shake
	else:
		cam.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.CHARS:
			if event.is_action_pressed("ui_left"):
				hud.chars_move(-1)
			elif event.is_action_pressed("ui_right"):
				hud.chars_move(1)
			elif event.is_action_pressed("ui_accept"):
				_on_char_chosen(hud.chars_selected_id())
		State.CREATE:
			if event.is_action_pressed("ui_accept"):
				hud.confirm_create()
		State.TOWN:
			var talk_key: bool = event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
			if talk_key:
				var npc := town.near_npc()
				if not npc.is_empty():
					_talk(npc)
			elif event.is_action_pressed("ui_cancel"):
				_open_town_menu()
		State.DIALOG:
			if event is InputEventKey and event.pressed and not event.echo:
				var di := int(event.keycode) - int(KEY_1)
				if di >= 0 and di < hud.dialog_count:
					_on_dialog_option(di)
				elif event.keycode == KEY_ESCAPE:
					_dialog_close()
		State.LOADOUT:
			if event.is_action_pressed("ui_accept"):
				hud.confirm_loadout()
			elif event.is_action_pressed("ui_cancel"):
				_on_loadout_cancel()
		State.PLAY:
			if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
				hud.toggle_hud()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_cancel"):
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
				elif event.keycode == KEY_R:
					_on_reroll()
		State.MODAL:
			if event.is_action_pressed("ui_cancel"):
				_close_modal()
		State.END:
			if _uploading:
				return
			if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
				_end_to_town()
			elif event is InputEventKey and event.pressed and event.keycode == KEY_B and Net.configured():
				_open_board()


## 创建角色 / 登录 / 开局选择时隐藏世界和 HUD，避免透出游戏画面
## 伪 2.5D：局内 / 村子斜俯视（view_tilt）加透视缩放（view_persp）；菜单不倾斜
func _set_tilt(on: bool, in_town: bool = false) -> void:
	Depth.tilt = clampf(Data.T("view_tilt"), 0.5, 1.0) if on else 1.0
	Depth.persp_k = (Data.T("view_persp_town") if in_town else Data.T("view_persp")) if on else 0.0     # 村子里远近差更夸张：能明显看出「远处的人 / 楼变小」


func _show_game(on: bool) -> void:
	_set_tilt(on)
	world.scale = Vector2(1.0, Depth.tilt)
	town.scale = Vector2(1.0, 1.0)
	world.visible = on
	hud.canvas.visible = on
	town.visible = false
	hud.show_town_hud(false)


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


## 登录成功：账号下的角色列表以服务器为准；选一个角色进村（没有角色就先创建）
func _after_login() -> void:
	_enter_character()


## 把服务器上当前角色的进度灌进本地缓存（修为 / 属性点 / 天赋 / 装备 / 银两 / 通关记录）
func _activate_online_char() -> void:
	Save.use_online_char(Net.char_id, Net.char_name, Net.school)
	Save.store_meta(Net.exp, Net.alloc)
	Save.set_meta_talents(Net.talents)
	Save.set_gear(Net.items, Net.equip)
	Save.store_silver_enh(Net.silver, Net.enh)
	Save.set_cleared(Net.cleared)
	_remember_last_char(Net.char_id)
	_enter_town()


func _on_account_requested() -> void:
	if state != State.TOWN and state != State.CHARS:
		return
	hud.hide_loadout()
	hud.hide_chars()
	if Net.logged_in():
		await _flush_pending()
		await Net.logout()
	_enter_auth("")


# ---------------------------------------------------------------------
# 角色与开局
# ---------------------------------------------------------------------

## 上次进入的角色（按账号记，选人界面默认选中它）
func _remember_last_char(id: String) -> void:
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	var lc: Variant = (ui as Dictionary).get("last_char", {})
	if not lc is Dictionary:
		lc = {}
	(lc as Dictionary)[Net.nick if Net.logged_in() else "_local"] = id
	(ui as Dictionary)["last_char"] = lc
	Save.data["ui"] = ui
	Save.save_data()


func _last_char() -> String:
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		return ""
	var lc: Variant = (ui as Dictionary).get("last_char", {})
	if not lc is Dictionary:
		return ""
	return str((lc as Dictionary).get(Net.nick if Net.logged_in() else "_local", ""))


func _char_list() -> Array:
	return Net.chars if Net.logged_in() else Save.chars()


## 选人界面；一个角色都没有就直接去创建
func _enter_character() -> void:
	hud.hide_create()
	if _char_list().is_empty():
		_enter_create()
		return
	state = State.CHARS
	_show_game(false)
	hud.show_chars(_char_list(), _last_char(), Net.logged_in())
	_flush_pending()


func _enter_create() -> void:
	state = State.CREATE
	_show_game(false)
	hud.hide_chars()
	hud.show_create(not _char_list().is_empty())


func _on_char_chosen(id: String) -> void:
	if state != State.CHARS or id == "":
		return
	if Net.logged_in():
		hud.set_chars_status("读取角色…")
		var res: Dictionary = await Net.select_char(id)
		if not bool(res.get("ok", false)):
			hud.set_chars_status(str(res.get("msg", "读取角色失败，请再试一次")), true)
			return
		hud.hide_chars()
		_activate_online_char()
	else:
		if Save.select_char(id):
			_remember_last_char(id)
			hud.hide_chars()
			_enter_town()


func _on_char_create_requested() -> void:
	if state == State.CHARS:
		_enter_create()


func _on_char_delete(id: String) -> void:
	if state != State.CHARS:
		return
	if Net.logged_in():
		hud.set_chars_status("删除中…")
		var res: Dictionary = await Net.delete_char(id)
		if not bool(res.get("ok", false)):
			hud.set_chars_status(str(res.get("msg", "删除失败，请再试一次")), true)
			return
	else:
		Save.delete_char(id)
	_enter_character()


var _debug_npc_done := false


func _enter_town() -> void:
	state = State.TOWN
	town.set_school(Save.school())
	_show_game(false)
	hud.hide_dialog()
	town.visible = true
	_set_tilt(true, true)
	town.scale = Vector2(1.0, Depth.tilt)
	hud.show_town_hud(true)
	_debug_place_near_npc()


## 仅限开发：后端指向本机时，地址里的 ?npc=<id> 让主角一进村就站在那个 NPC 面前（端到端测试用）
func _debug_place_near_npc() -> void:
	if _debug_npc_done or not OS.has_feature("web") or not Net.api_url.begins_with("http://localhost"):
		return
	_debug_npc_done = true
	var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('npc') || ''")
	if q == null or str(q) == "":
		return
	for n in town.npcs:
		if str(n["id"]) == str(q):
			town.player_pos = (n["pos"] as Vector2) + Vector2(0, 46)


func _enter_loadout(map_id: String = "") -> void:
	if map_id != "":
		current_map = map_id
	stage_bgm = current_map if ResourceLoader.exists("res://assets/bgm/%s.ogg" % current_map) else "black_wind"
	state = State.LOADOUT
	_show_game(false)
	hud.show_loadout(Save.school(), current_map)


func _on_loadout_cancel() -> void:
	if state != State.LOADOUT:
		return
	hud.hide_loadout()
	_enter_town()


## 创建角色：选流派 + 起名字；在线时角色建在服务器上，单机时存在本机
func _on_created(school_id: String, char_name: String) -> void:
	if state != State.CREATE:
		return
	if Net.logged_in():
		hud.set_create_status("创建中…")
		var res: Dictionary = await Net.create_char(char_name, school_id)
		if not bool(res.get("ok", false)):
			hud.set_create_status(str(res.get("msg", "创建失败，请再试一次")))
			return
		hud.hide_create()
		_activate_online_char()
		return
	var id := Save.add_char(char_name, school_id)
	if id == "":
		hud.set_create_status("最多只能有 %d 个角色" % Save.MAX_CHARS)
		return
	Save.select_char(id)
	_remember_last_char(id)
	hud.hide_create()
	_enter_town()


## 回到选人界面（小镇掌柜处）
func _on_switch_char() -> void:
	if state != State.DIALOG and state != State.TOWN:
		return
	hud.hide_dialog()
	hud.hide_loadout()
	_enter_character()


func _on_loadout(starter_id: String, qinggong_id: String) -> void:
	if state != State.LOADOUT:
		return
	_flush_pending()
	Save.set_last_starter(starter_id)
	Build.apply_to(world, Save.meta_alloc(), Save.meta_talents(), Save.equip(), Save.school())
	world.meta_level = int(Meta.progress(Save.meta_exp())["level"])
	world.start_run(starter_id, qinggong_id, current_map, hud.difficulty_factors())
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
		choice_is_chest = true
		choice_title = "击败小 Boss，获得秘籍！选择本局的专属强化（按 1 / 2 / 3 或点击）"
		hud.show_choices(choices, choice_title)
		state = State.CHOOSE
	elif world.pending_levels > 0:
		choices = world.roll_choices()
		choice_is_chest = false
		var has_rr := GameWorld.rerolls_for_level(world.meta_level) > 0
		choice_title = "突破！选择一项领悟（按 1 / 2 / 3 或点击" + ("；R = 另觅机缘）" if has_rr else "）")
		hud.show_choices(choices, choice_title, world.rerolls_left if has_rr else -1)
		state = State.CHOOSE


## 另觅机缘：重抽这一轮的升级卡（秘籍选卡不可重抽）
func _on_reroll() -> void:
	if state != State.CHOOSE or choice_is_chest or not world.can_reroll():
		return
	Sfx.play("card_pick", 0.05, -1.0)
	choices = world.use_reroll(choices)
	hud.show_choices(choices, choice_title, world.rerolls_left)


func _on_choice(i: int) -> void:
	if state != State.CHOOSE or i >= choices.size():
		return
	Sfx.play("card_pick", 0.03, -1.0)
	world.apply_choice(choices[i])
	hud.hide_choices()
	state = State.PLAY
	_check_pending()


# ---------------------------------------------------------------------
# 结算与成绩上传
# ---------------------------------------------------------------------

func _on_pause_resume() -> void:
	if state == State.PAUSED:
		state = State.PLAY
		hud.hide_overlay()


## 放弃本局：按阵亡结算（成绩 / 修为照常），再从结算界面回村
func _on_pause_abandon() -> void:
	if state != State.PAUSED:
		return
	hud.hide_overlay()
	world.over = true
	world.won = false
	_on_end(false)


## 局结束后回到小镇（不回登录画面；已登录状态、局外成长、装备都保留）
var _uploading := false       # 结算成绩上传中：不允许离开结算页（上传结束——成功或失败——才放行）


func _end_to_town() -> void:
	if _uploading:
		return
	hud.hide_overlay()
	_enter_town()


func _on_end(won: bool) -> void:
	state = State.END
	hud.hide_choices()
	hud.show_end(won)
	Sfx.play("win_jingle" if won else "lose_jingle", 0.0, -2.0, 1.0)
	if not Net.configured():
		# 单机：本地直接结算修为，通关掉落装备
		if world.time >= 30.0:
			var local := Save.add_run_exp(world.run_summary())
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var sm := world.run_summary()
			var minis := clampi(int(sm["bosses"]) - (1 if won else 0), 0, 3)
			local["drops"] = Gear.run_drops(rng, minis, won, Meta.comp_of(sm.get("difficulty", {})), str(sm.get("map", "black_wind")))
			Save.add_items(local["drops"])
			hud.set_end_extra(_exp_line(local))
		return
	if not Net.logged_in() or world.time < 30.0:
		return
	_uploading = true
	hud.set_end_locked(true)
	hud.set_end_extra("成绩上传中…")
	var sent_char := Net.char_id
	var summary := world.run_summary()
	var res: Dictionary = await Net.submit_run(summary, sent_char)
	_uploading = false
	hud.set_end_locked(false)
	var retry := not bool(res.get("ok", false)) and RETRY_ERRS.has(str(res.get("err", "")))
	if retry:                    # 没传上去：存起来，下次进关卡 / 进角色画面 / 退出登录前自动重传
		Save.add_pending(Net.nick, sent_char, summary)
	if Net.char_id != sent_char or not Net.logged_in():        # 等上传期间已经换了角色 / 退出登录：不要把结果写进别的角色
		return
	if bool(res.get("ok", false)):
		_apply_submit(res)
		if state != State.END:
			return
		if bool(res.get("dup", false)):
			hud.set_end_extra("这局成绩之前已经上传过了。")
			return
		var ranks: Dictionary = res.get("ranks", {})
		var line := "已上榜：总分榜第 %d 名" % int(ranks.get("score", 0))
		if bool(res.get("best", false)):
			line += "　（个人最高分！）"
		hud.set_end_extra(line + "\n" + _exp_line(res))
	elif state == State.END:
		if retry:
			hud.set_end_extra("成绩没能上传（%s）。已保存在本机，下次进入关卡、回到角色选择或退出登录时会自动重试。" % str(res.get("msg", "未知错误")))
		else:
			hud.set_end_extra("成绩没能上传：%s" % str(res.get("msg", "未知错误")))


const RETRY_ERRS := ["net", "offline", "too_fast", "server", "bad_token"]
var _flushing := false


## 把上传成功的结果写进当前角色的本地缓存，并刷新小镇上的等级 / 银两
func _apply_submit(res: Dictionary) -> void:
	Save.store_meta(Net.exp, Save.meta_alloc())
	if res.get("drops", []) is Array:
		Save.add_items(res["drops"])
	Save.store_silver_enh(int(res.get("silver", Net.silver)), Save.enh())
	Save.set_cleared(Net.cleared)
	if state == State.TOWN or state == State.DIALOG:
		hud.show_town_hud(true)


## 补传之前没传上去的成绩（只补当前登录账号的）；一条失败就停，等下一次机会
func _flush_pending() -> void:
	if _flushing or not Net.configured() or not Net.logged_in():
		return
	_flushing = true
	for e in Save.pending_runs().duplicate():
		if not e is Dictionary or str(e.get("nick", "")) != Net.nick:
			continue
		var cid := str(e.get("char", ""))
		var res: Dictionary = await Net.submit_run(e.get("summary", {}), cid)
		if not Net.logged_in():
			break
		if bool(res.get("ok", false)):
			Save.remove_pending(e)
			if cid == Net.char_id:
				_apply_submit(res)
		elif RETRY_ERRS.has(str(res.get("err", ""))):
			break
		else:
			Save.remove_pending(e)        # 服务器明确拒绝（成绩无效等）：重传也没用，丢掉
	_flushing = false


func _exp_line(r: Dictionary) -> String:
	var line := "修为 +%d　银两 +%d　局外 Lv%d" % [int(r.get("gained", 0)), int(r.get("silverGained", 0)), int(r.get("level", 1))]
	if bool(r.get("capped", false)):
		line += "　（这张图的修为已到上限，去更高的关卡历练吧）"
	if bool(r.get("levelUp", false)):
		line += "　升级了！获得 3 个属性点、2 个天赋点"
	var drops: Variant = r.get("drops", [])
	if drops is Array and not (drops as Array).is_empty():
		var names: Array = []
		for c in drops:
			var it := Gear.make(str(c), Save.school())
			if not it.is_empty():
				names.append("【%s】%s" % [it["rarity_name"], it["name"]])
		line += "\n大 Boss 掉落：" + "　".join(names) + "（开局界面「装备」里穿戴）"
	return line


# ---------------------------------------------------------------------
# 排行榜 / 反馈（弹层）
# ---------------------------------------------------------------------

func _open_modal() -> void:
	modal_return = state
	state = State.MODAL
	if modal_return == State.LOADOUT:
		hud.hide_loadout()
	elif modal_return == State.TOWN:
		hud.show_town_hud(false)
	else:
		hud.overlay.visible = false      # 从结算界面打开时，隐藏底下的结算文字，避免透出


func _open_board() -> void:
	if state != State.TOWN and state != State.END:
		return
	_open_modal()
	hud.show_board()
	_load_board(hud.board_kind)


func _load_board(kind: String) -> void:
	var res: Dictionary = await Net.board(kind, hud.board_group_only, hud.board_map)
	hud.update_board(kind, res)


# ---------------------------------------------------------------------
# 村子里的 NPC 对话
# ---------------------------------------------------------------------

func _dlg(npc: Dictionary, text: String, opts: Array) -> void:
	state = State.DIALOG
	dialog_npc = npc
	dialog_actions = []
	var labels: Array = []
	for o in opts:
		labels.append({"label": o["label"], "enabled": o.get("enabled", true)})
		dialog_actions.append(str(o["action"]))
	hud.show_dialog("%s　·　%s" % [npc["name"], npc["title"]], text, labels, npc.get("tex"))


func _talk(npc: Dictionary) -> void:
	var opts: Array = []
	var greet := str(npc["greet"])
	match str(npc["id"]):
		"clerk":
			opts = [{"label": "出发历练（选择地图）", "action": "depart"}, {"label": "再逛逛", "action": "close"}]
		"smith":
			greet += "\n\n你有银两 %d。每局结算都会得到银两，丢弃（分解）装备也能换银两。" % Save.silver()
			opts = [{"label": "强化装备（消耗银两，最高 +%d）" % Gear.enhance_max(), "action": "enhance"},
				{"label": "整备装备（穿戴 / 丢弃）", "action": "gear"}, {"label": "告辞", "action": "close"}]
		"herbalist":
			opts = [{"label": "告辞", "action": "close"}]
		"master":
			var mp := Meta.progress(Save.meta_exp())
			var free_pts: int = Meta.points_total(int(mp["level"])) - Meta.points_used(Save.meta_alloc())
			var free_t: int = Talents.total_points(int(mp["level"])) - Talents.spent(Save.meta_talents())
			greet += "\n\n你现在是局外 Lv%d，未分配属性点 %d、天赋点 %d。" % [mp["level"], free_pts, free_t]
			opts = [{"label": "属性与天赋（角色成长）", "action": "meta"}, {"label": "告辞", "action": "close"}]
		"innkeeper":
			var online := Net.configured() and Net.logged_in()
			opts = [{"label": "江湖排行榜" + ("" if online else "（需要登录）"), "action": "board", "enabled": online},
				{"label": "给我们提意见（反馈）" + ("" if online else "（需要登录）"), "action": "feedback", "enabled": online},
				{"label": "切换角色", "action": "switch_char"},
				{"label": "退出登录" if Net.configured() else "退出登录（未联网）", "action": "logout", "enabled": Net.configured()},
				{"label": "告辞", "action": "close"}]
		"sage":
			opts = [{"label": "翻阅百晓册（玩法 / 招式 / 心法 / 轻功）", "action": "guide"}, {"label": "告辞", "action": "close"}]
		_:
			opts = [{"label": "告辞", "action": "close"}]
	_dlg(npc, greet, opts)


## 小镇里按 Esc：菜单（继续 / 返回角色选择 / 退出登录）
func _open_town_menu() -> void:
	var online := Net.configured()
	_dlg({"id": "menu", "name": "菜单", "title": "小镇", "greet": ""}, "要去哪儿？",
		[{"label": "继续游戏", "action": "close"},
		{"label": "返回角色选择", "action": "switch_char"},
		{"label": "致谢", "action": "credits"},
		{"label": "退出登录（返回登录画面）" if online else "退出登录（未联网，无登录画面）", "action": "logout", "enabled": online}])


func _dialog_close() -> void:
	hud.hide_dialog()
	state = State.TOWN


func _on_dialog_option(i: int) -> void:
	if state != State.DIALOG or i < 0 or i >= dialog_actions.size():
		return
	var act: String = str(dialog_actions[i])
	if act.begins_with("map:"):
		hud.hide_dialog()
		_enter_loadout(act.substr(4))
		return
	match act:
		"close":
			_dialog_close()
		"credits":
			hud.show_credits()
		"talk":
			_talk(dialog_npc)
		"depart":
			var opts: Array = []
			for id in Data.maps:
				var m: Dictionary = Data.maps[id]
				var lv := int(Meta.progress(Save.meta_exp())["level"])
				var stars := "★".repeat(int(m["stars"]))
				if not bool(m["enabled"]):
					opts.append({"label": "%s　%s　（敬请期待 · 需局外 Lv%d）" % [m["name"], stars, int(m["min_meta_level"])], "action": "close", "enabled": false})
				elif lv < int(m["min_meta_level"]):
					opts.append({"label": "%s　%s　（需局外 Lv%d）" % [m["name"], stars, int(m["min_meta_level"])], "action": "close", "enabled": false})
				elif not Save.map_unlocked(str(id)):
					opts.append({"label": "%s　%s　（需先通关 %s）" % [m["name"], stars, Data.maps[str(m["requires_clear"])]["name"]], "action": "close", "enabled": false})
				else:
					var rec := ""
					for r in Save.recommend_status(str(id)):
						rec += "　%s %s" % ["✔" if bool(r["ok"]) else "✘", r["label"]]
					opts.append({"label": "%s　%s　%s　【%s】%s" % [m["name"], stars, m["desc"], m.get("suggest", ""), ("\n推荐：" + rec) if rec != "" else ""], "action": "map:" + str(id)})
			opts.append({"label": "返回", "action": "talk"})
			_dlg(dialog_npc, "想去哪儿历练？", opts)
		"switch_char":
			hud.hide_dialog()
			state = State.TOWN
			_on_switch_char()
		"gear", "enhance", "meta", "board", "feedback", "guide", "logout":
			hud.hide_dialog()
			state = State.TOWN
			match act:
				"gear": _open_gear()
				"enhance": _open_smith()
				"meta": _open_meta()
				"board": _open_board()
				"feedback": _open_feedback()
				"guide":
					_open_modal()
					hud.show_guide()
				"logout": _on_account_requested()


func _open_meta() -> void:
	if state != State.TOWN and state != State.LOADOUT:
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


func _open_talents() -> void:
	if state != State.MODAL:
		return
	hud.hide_meta()
	hud.show_talents()


func _on_talents_saved(t: Dictionary) -> void:
	if state != State.MODAL:
		return
	if Net.logged_in():
		hud.set_talents_status("保存中…", false)
		var res: Dictionary = await Net.save_talents(t)
		if not bool(res.get("ok", false)):
			hud.set_talents_status(str(res.get("msg", "保存失败，请稍后再试")), true)
			return
	Save.set_meta_talents(t)
	_close_modal()


func _open_gear() -> void:
	if state != State.TOWN and state != State.LOADOUT:
		return
	_open_modal()
	hud.show_gear()


func _open_smith() -> void:
	if state != State.TOWN:
		return
	_open_modal()
	hud.show_smith()


## 铁匠强化：联网时由服务器扣银两、记录等级；单机直接改本地存档
func _on_enhance(code: String) -> void:
	if state != State.MODAL:
		return
	hud.set_smith_status("锻打中…", false)
	var res: Dictionary
	if Net.logged_in():
		res = await Net.enhance(code)
		if bool(res.get("ok", false)):
			Save.store_silver_enh(Net.silver, Net.enh)
	else:
		res = Save.enhance_local(code)
	if state != State.MODAL:
		return
	if bool(res.get("ok", false)):
		Sfx.play("gear_upgrade")
		hud.show_smith("强化成功！+%d（花费 %d 银两）" % [int(res["level"]), int(res["cost"])])
	else:
		Sfx.play("gear_fail")
		hud.set_smith_status(str(res.get("msg", "强化失败，请稍后再试")), true)


func _on_gear_saved(equip: Dictionary, discard: Array) -> void:
	if state != State.MODAL:
		return
	if Net.logged_in():
		hud.set_gear_status("保存中…", false)
		var res: Dictionary = await Net.save_gear(equip, discard)
		if not bool(res.get("ok", false)):
			hud.set_gear_status(str(res.get("msg", "保存失败，请稍后再试")), true)
			return
		Save.set_gear(Net.items, Net.equip)
		Save.store_silver_enh(Net.silver, Net.enh)
	else:
		var inv := Save.items()
		Save.discard_local(discard)
		for c in discard:
			inv.erase(c)
		Save.set_gear(inv, equip)
	_close_modal()


func _open_feedback() -> void:
	if state != State.TOWN and state != State.LOADOUT:
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
	hud.hide_talents()
	hud.hide_gear()
	hud.hide_smith()
	hud.hide_guide()
	state = modal_return
	if modal_return == State.LOADOUT:
		_enter_loadout()
	elif modal_return == State.TOWN:
		_enter_town()
	else:
		hud.overlay.visible = true
