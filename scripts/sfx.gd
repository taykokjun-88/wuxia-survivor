extends Node
## 战斗音效管理器（建议在 project.godot 的 [autoload] 注册为 Sfx="*res://scripts/sfx.gd"）。
## 1. 启动时在内存生成极短的 16-bit PCM（AudioStreamWAV）战斗音效，无需外部素材即可直接跑通打击感；
##    若 res://assets/sfx/<id>.ogg 或 .wav 存在，则自动优先加载真实采样。
## 2. 内置冷却锁（防同屏百怪齐中炸音）、并发声道上限、音高随机抖动（±10%）与 20 路播放器复用池。

const SAMPLE_RATE := 22050
const POOL_SIZE := 8               # 参考 RO 局内清晰度：同时最多 8 路，避免百怪齐中叠成一团白噪音，同时大幅降低 Web Audio 开销

var enabled := true
var _players: Array[AudioStreamPlayer] = []
var _playing_id: Array[String] = []
var _playing_cat: Array[String] = []
var _streams: Dictionary = {}
var _last_ms: Dictionary = {}
var _cat_last_ms: Dictionary = {}
var _exp_streak := 0
var _exp_last_ms := 0

# id -> [cooldown_ms, max_voices, priority, base_vol_db, category]
# 音量层次参考 RO（仙境传说）：
#   高频底噪（普通命中 / 拾取 / 小怪死）：-11 ~ -14 dB，轻巧点缀绝不吵耳
#   招式挥砍 / 施法：-7 ~ -9 dB，全局出招节流防多招同帧齐吼
#   清晰反馈（暴击 / 格挡 / 破防 / 轻功）：-3 ~ -5 dB，清脆透出
#   关键事件（升级 / Boss / 觉醒 / 受击）：-1 ~ -2 dB，最高优先级
const RULES := {
	"hit_fist": [95, 1, 1, -11.0, "hit"],
	"hit_sword": [95, 1, 1, -11.0, "hit"],
	"hit_blade": [95, 1, 1, -11.0, "hit"],
	"hit_crit": [110, 1, 3, -5.0, "hit"],
	"vuln_break": [160, 1, 2, -5.5, "fb"],
	"block_shield": [140, 1, 2, -5.0, "fb"],
	"player_hurt": [320, 1, 4, -2.0, "evt"],
	"enemy_death": [180, 1, 0, -14.0, "amb"],
	"dash_qg": [160, 1, 2, -5.0, "fb"],
	"realm_ying": [1400, 1, 3, -4.0, "evt"],
	"burst_ult": [500, 1, 4, -2.0, "evt"],
	"pickup_exp": [115, 1, 0, -12.0, "amb"],
	"level_up": [250, 1, 4, -1.5, "evt"],
	"boss_warn": [1500, 1, 5, -1.0, "evt"],
	"armor_break": [320, 1, 4, -3.5, "evt"],
	"sw_slash": [150, 1, 1, -8.5, "cast"],
	"sw_heavy": [240, 1, 2, -7.0, "cast"],
	"sw_thrust": [150, 1, 1, -8.5, "cast"],
	"sw_proj": [160, 1, 1, -9.0, "cast"],
	"dugu_flash": [95, 2, 2, -7.5, "cast"],
	"dugu_awaken": [1000, 1, 5, -1.0, "evt"],
	"fist_punch": [140, 1, 1, -8.5, "cast"],
	"palm_wave": [180, 1, 1, -8.5, "cast"],
	"enemy_ranged": [260, 1, 0, -11.5, "amb"],
	"boss_cleave": [260, 1, 3, -4.0, "evt"],
	"burst_break": [320, 1, 4, -3.5, "evt"],
	# 剑
	"sw_ring": [220, 1, 2, -8.0, "cast"], "sw_multi": [220, 1, 2, -8.5, "cast"], "sw_blink": [180, 1, 2, -7.5, "cast"], "sw_snake": [180, 1, 1, -9.0, "cast"], "sw_yitian": [320, 1, 3, -6.0, "cast"],
	# 刀
	"bl_slash": [150, 1, 1, -8.5, "cast"], "bl_heavy": [220, 1, 2, -7.0, "cast"], "bl_proj": [170, 1, 1, -9.0, "cast"], "bl_fire": [240, 1, 2, -7.5, "cast"], "bl_blood": [180, 1, 1, -8.5, "cast"],
	"bl_wheel": [260, 1, 2, -8.0, "cast"], "bl_quake": [300, 1, 3, -6.5, "cast"], "bl_spin": [240, 1, 2, -8.0, "cast"], "bl_dragon": [420, 1, 4, -5.0, "cast"],
	# 拳 / 掌
	"fist_finger": [150, 1, 1, -9.0, "cast"], "fist_quake": [280, 1, 3, -6.5, "cast"], "fist_vajra": [280, 1, 3, -6.5, "cast"],
	"palm_multi": [200, 1, 1, -8.5, "cast"], "palm_dragon": [240, 1, 2, -7.5, "cast"], "palm_soft": [240, 1, 2, -8.0, "cast"],
	# 界面 / 结算
	"footstep": [200, 1, 0, -9.0, "ui"], "ui_click": [45, 2, 2, -4.0, "ui"], "ui_confirm": [60, 1, 3, -3.0, "ui"], "ui_back": [60, 1, 3, -3.0, "ui"], "card_pick": [80, 1, 3, -2.5, "ui"], "chest_open": [300, 1, 3, -3.0, "evt"],
	"block_staff": [140, 1, 2, -5.0, "fb"], "block_swing": [180, 1, 2, -6.5, "fb"], "sp_thrust": [150, 1, 1, -8.5, "cast"], "sp_multi": [180, 1, 2, -8.5, "cast"], "sp_pierce": [240, 1, 3, -6.5, "cast"], "sp_staff_heavy": [200, 1, 2, -7.5, "cast"],
	"sp_staff_sweep": [220, 1, 2, -7.5, "cast"], "sp_dragon": [420, 1, 4, -5.0, "cast"], "bagua_shift": [1500, 1, 4, -3.0, "evt"], "bagua_bad": [1100, 1, 1, -9.0, "amb"], "xiao_note": [800, 1, 3, -4.5, "evt"], "bell_ring": [600, 1, 3, -4.5, "evt"],
	"peach_petal": [450, 1, 2, -8.0, "amb"], "poison_dart": [200, 1, 0, -11.0, "amb"],
	"gear_upgrade": [300, 1, 3, -2.0, "ui"], "gear_fail": [300, 1, 3, -2.0, "ui"], "win_jingle": [2000, 1, 5, -1.0, "evt"], "lose_jingle": [2000, 1, 5, -1.0, "evt"],
}

# 全局分类并发与节流：[category_cooldown_ms, category_max_voices]
const CAT_LIMITS := {
	"hit": [85, 2],      # 打击感：同瞬间最多响 1~2 声，清脆不糊
	"cast": [125, 2],    # 出招：多自动技能错峰发声，不齐吼
	"amb": [120, 2],     # 经验球 / 小怪死亡 / 杂兵箭矢：轻巧节流
	"fb": [70, 2],       # 格挡 / 破绽 / 轻功
}

var _variants: Dictionary = {}     # id -> [AudioStream]：<id>_1 / _2 / _3 …（命中 / 受击等随机轮换，避免听腻）

const SKILL_MAP := {
	# 剑侠：细、亮、带「铮」
	"kuang_feng": "sw_slash", "qingsong": "sw_thrust", "zhongjian": "sw_heavy", "taiji_sword": "sw_ring",
	"wanjian": "sw_multi", "yunv": "sw_slash", "pixie": "sw_blink", "jinshe": "sw_snake", "yitian": "sw_yitian", "dugu": "sw_proj",
	# 刀客：宽、重
	"wuhu_blade": "bl_heavy", "kuangfeng_blade": "bl_slash", "hujia_blade": "bl_proj", "ranmu_blade": "bl_fire", "xuedao": "bl_blood",
	"fanliangyi": "bl_wheel", "xuanxu_blade": "bl_quake", "yuanyang_blade": "bl_spin", "tulong_art": "bl_dragon",
	# 武者：拳闷、掌有气浪
	"chain_fist": "fist_punch", "point_finger": "fist_finger", "quake_fist": "fist_quake", "vajra_fist": "fist_vajra",
	# 杨家将：枪 = 尖锐刺 / 贯；棍 = 厚重闷响
	"yangjia_spear": "sp_thrust", "meihua_spear": "sp_multi", "baima_spear": "sp_thrust", "wuming_spear": "sp_pierce",
	"shaolin_staff": "sp_staff_sweep", "panlong_staff": "sp_dragon", "dagou_staff": "sp_staff_heavy", "fengmo_staff": "sp_staff_sweep", "xiangmo_staff": "sp_staff_heavy",
	"yue_palm": "palm_dragon", "whirl_palm": "palm_wave", "eight_waste": "palm_multi", "taiji": "palm_soft", "cloud_palm": "palm_wave",
}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui: Variant = Save.data.get("ui", {})
	if ui is Dictionary and bool((ui as Dictionary).get("sfx_off", false)):
		enabled = false
	_setup_bus()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus_name()
		add_child(p)
		_players.append(p)
		_playing_id.append("")
		_playing_cat.append("")
	_build_all_streams()


## 音效开关（暂停菜单里切换，记在本地存档的 ui 里）
func set_enabled(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	enabled = on
	var ui: Variant = Save.data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	(ui as Dictionary)["sfx_off"] = not on
	Save.data["ui"] = ui
	Save.save_data()


func _sfx_bus_name() -> String:
	return "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"


func _setup_bus() -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, -2.0)      # 给 BGM 留出空间，久听不累
		var eq := AudioEffectEQ6.new()                # 柔化 3.2kHz / 10kHz 刺耳高频，贴近 RO 的圆润听感
		eq.set_band_gain_db(4, -1.5)
		eq.set_band_gain_db(5, -3.5)
		AudioServer.add_bus_effect(idx, eq)
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -2.0
		lim.threshold_db = -5.0
		AudioServer.add_bus_effect(idx, lim)


func play(id: String, pitch_jitter: float = 0.08, vol_db: float = 0.0, pitch_override: float = -1.0) -> void:
	if not enabled or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	var rule: Array = RULES.get(id, [120, 1, 1, -8.0, "cast"])
	if now - int(_last_ms.get(id, 0)) < int(rule[0]):
		return
	if _active_count(id) >= int(rule[1]):
		return
	var cat: String = str(rule[4]) if rule.size() >= 5 else "cast"
	var prio: int = int(rule[2])
	if CAT_LIMITS.has(cat):
		var cl: Array = CAT_LIMITS[cat]
		# 暴击（prio >= 3）在打击类里可按一半间隔穿透普通命中，保留清晰暴击反馈
		var min_gap := int(cl[0]) / 2 if (cat == "hit" and prio >= 3) else int(cl[0])
		if now - int(_cat_last_ms.get(cat, 0)) < min_gap:
			return
		if _active_cat_count(cat) >= int(cl[1]):
			return
	var idx := _borrow_slot(prio)
	if idx < 0:
		return
	var p := _players[idx]
	_playing_id[idx] = id
	_playing_cat[idx] = cat
	var vs: Array = _variants.get(id, [])
	p.stream = vs[randi() % vs.size()] if not vs.is_empty() else _streams[id]
	if pitch_override > 0.0:
		p.pitch_scale = pitch_override
	else:
		p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	var base_db := float(rule[3]) if rule.size() >= 4 else -6.0
	p.volume_db = base_db + vol_db
	p.play()
	_last_ms[id] = now
	_cat_last_ms[cat] = now


func play_skill(skill_id: String, combo_step: int = 0) -> void:
	if skill_id == "dugu" and combo_step > 0:
		play("dugu_flash", 0.04, 0.0, 1.0 + minf(0.24, combo_step * 0.025))
		return
	play(str(SKILL_MAP.get(skill_id, "sw_slash")), 0.08, 0.0)


func play_exp() -> void:
	var now := Time.get_ticks_msec()
	_exp_streak = mini(6, _exp_streak + 1) if now - _exp_last_ms < 450 else 0
	_exp_last_ms = now
	play("pickup_exp", 0.02, 0.0, 1.0 + _exp_streak * 0.025)


func _active_count(id: String) -> int:
	var c := 0
	for i in _players.size():
		if _players[i].playing and _playing_id[i] == id:
			c += 1
	return c


func _active_cat_count(cat: String) -> int:
	var c := 0
	for i in _players.size():
		if _players[i].playing and _playing_cat[i] == cat:
			c += 1
	return c


func _borrow_slot(prio: int) -> int:
	var worst := -1
	var worst_prio := prio
	for i in _players.size():
		if not _players[i].playing:
			return i
		var p_id := _playing_id[i]
		var r: Array = RULES.get(p_id, [120, 1, 1, -8.0, "cast"])
		if int(r[2]) < worst_prio:
			worst_prio = int(r[2])
			worst = i
	return worst


func _build_all_streams() -> void:
	for id in RULES:
		var vs: Array = []
		for i in range(1, 7):
			for ext in ["ogg", "wav"]:
				var vp := "res://assets/sfx/%s_%d.%s" % [id, i, ext]
				if ResourceLoader.exists(vp):
					vs.append(load(vp))
					break
		if not vs.is_empty():
			_variants[id] = vs
			_streams[id] = vs[0]
			continue
		var ogg := "res://assets/sfx/%s.ogg" % id
		var wav := "res://assets/sfx/%s.wav" % id
		if ResourceLoader.exists(ogg):
			_streams[id] = load(ogg)
			continue
		if ResourceLoader.exists(wav):
			_streams[id] = load(wav)
			continue
		_streams[id] = _synth(id)


func _synth(id: String) -> AudioStreamWAV:
	match id:
		"hit_fist": return _make_thump(0.075, 160.0, 55.0, 0.35)
		"hit_sword": return _make_slash(0.085, 2200.0, 0.35, 0.25)
		"hit_crit": return _make_chime(0.14, [880.0, 1320.0, 1760.0], 0.45, true)
		"vuln_break": return _make_chime(0.16, [1174.0, 1568.0], 0.40, false)
		"block_shield": return _make_thump(0.12, 240.0, 110.0, 0.30)
		"player_hurt": return _make_thump(0.18, 130.0, 42.0, 0.55)
		"enemy_death": return _make_noise(0.09, 0.16, 0.35)
		"dash_qg": return _make_noise(0.15, 0.30, 0.70)
		"realm_ying": return _make_chime(0.35, [330.0, 495.0], 0.30, false)
		"burst_ult": return _make_chime(0.48, [220.0, 440.0, 660.0], 0.50, true)
		"pickup_exp": return _make_chime(0.065, [1046.0, 1568.0], 0.25, false)
		"level_up": return _make_chime(0.40, [523.25, 659.25, 783.99], 0.40, false)
		"boss_warn": return _make_chime(0.75, [110.0, 165.0, 220.0], 0.55, true)
		"armor_break": return _make_chime(0.45, [196.0, 392.0, 784.0], 0.50, true)
		"sw_slash", "sw_proj": return _make_slash(0.10, 1800.0, 0.32, 0.40)
		"sw_heavy", "boss_cleave": return _make_thump(0.24, 150.0, 48.0, 0.50)
		"sw_thrust", "dugu_flash": return _make_slash(0.08, 2600.0, 0.36, 0.20)
		"dugu_awaken": return _make_chime(0.65, [440.0, 659.25, 880.0, 1318.5], 0.50, true)
		"fist_punch": return _make_thump(0.07, 190.0, 70.0, 0.38)
		"palm_wave": return _make_noise(0.16, 0.32, 0.55)
		"enemy_ranged": return _make_slash(0.07, 1400.0, 0.20, 0.20)
	return _make_thump(0.08, 180.0, 60.0, 0.30)


func _pack_pcm(samples: PackedFloat32Array) -> AudioStreamWAV:
	var buf := PackedByteArray()
	buf.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampi(int(samples[i] * 32767.0), -32768, 32767)
		buf[i * 2] = v & 0xFF
		buf[i * 2 + 1] = (v >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.data = buf
	return s


func _make_thump(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := pow(1.0 - t, 2.2)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		out[i] = sin(phase) * env * amp
	return _pack_pcm(out)


func _make_noise(dur: float, amp: float, smooth: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.5)
		var rnd := randf_range(-1.0, 1.0)
		lp = lerpf(rnd, lp, smooth)
		out[i] = lp * env * amp
	return _pack_pcm(out)


func _make_slash(dur: float, tone: float, amp: float, noise_mix: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := pow(1.0 - t, 1.8)
		phase += TAU * lerpf(tone, tone * 0.45, t) / float(SAMPLE_RATE)
		var sig := sin(phase) * (1.0 - noise_mix) + randf_range(-1.0, 1.0) * noise_mix
		out[i] = sig * env * amp
	return _pack_pcm(out)


func _make_chime(dur: float, freqs: Array, amp: float, punch: bool) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var inv := 1.0 / float(maxi(1, freqs.size()))
	for i in n:
		var t := float(i) / float(n)
		var env := pow(1.0 - t, 2.0)
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * (float(i) / float(SAMPLE_RATE))) * inv
		if punch and t < 0.18:
			v += sin(TAU * 90.0 * (float(i) / float(SAMPLE_RATE))) * (1.0 - t / 0.18) * 0.5
		out[i] = v * env * amp
	return _pack_pcm(out)
