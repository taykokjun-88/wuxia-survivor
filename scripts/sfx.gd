extends Node
## 战斗音效管理器（建议在 project.godot 的 [autoload] 注册为 Sfx="*res://scripts/sfx.gd"）。
## 1. 启动时在内存生成极短的 16-bit PCM（AudioStreamWAV）战斗音效，无需外部素材即可直接跑通打击感；
##    若 res://assets/sfx/<id>.ogg 或 .wav 存在，则自动优先加载真实采样。
## 2. 内置冷却锁（防同屏百怪齐中炸音）、并发声道上限、音高随机抖动（±10%）与 20 路播放器复用池。

const SAMPLE_RATE := 22050
const POOL_SIZE := 20

var enabled := true
var _players: Array[AudioStreamPlayer] = []
var _playing_id: Array[String] = []
var _streams: Dictionary = {}
var _last_ms: Dictionary = {}
var _exp_streak := 0
var _exp_last_ms := 0

# id -> [cooldown_ms, max_voices, priority]
const RULES := {
	"hit_fist": [45, 3, 1],
	"hit_sword": [45, 3, 1],
	"hit_crit": [55, 3, 3],
	"vuln_break": [80, 2, 2],
	"block_shield": [90, 2, 2],
	"player_hurt": [250, 1, 4],
	"enemy_death": [60, 2, 0],
	"dash_qg": [120, 2, 2],
	"realm_ying": [1000, 1, 3],
	"burst_ult": [400, 1, 4],
	"pickup_exp": [35, 4, 0],
	"level_up": [200, 1, 4],
	"boss_warn": [1500, 1, 5],
	"armor_break": [300, 1, 4],
	"sw_slash": [75, 3, 1],
	"sw_heavy": [180, 2, 2],
	"sw_thrust": [75, 3, 1],
	"sw_proj": [80, 3, 1],
	"dugu_flash": [35, 4, 2],
	"dugu_awaken": [1000, 1, 5],
	"fist_punch": [65, 3, 1],
	"palm_wave": [110, 2, 1],
	"enemy_ranged": [140, 2, 1],
	"boss_cleave": [220, 1, 3],
	"burst_break": [300, 1, 4],
	"hit_blade": [45, 3, 1],
	# 剑
	"sw_ring": [150, 2, 2], "sw_multi": [140, 2, 2], "sw_blink": [120, 2, 2], "sw_snake": [100, 3, 1], "sw_yitian": [300, 1, 3],
	# 刀
	"bl_slash": [80, 3, 1], "bl_heavy": [180, 2, 2], "bl_proj": [90, 3, 1], "bl_fire": [200, 2, 2], "bl_blood": [90, 3, 1],
	"bl_wheel": [220, 1, 2], "bl_quake": [260, 1, 3], "bl_spin": [200, 2, 2], "bl_dragon": [400, 1, 4],
	# 拳 / 掌
	"fist_finger": [75, 3, 1], "fist_quake": [260, 1, 3], "fist_vajra": [260, 1, 3],
	"palm_multi": [140, 2, 1], "palm_dragon": [200, 2, 2], "palm_soft": [200, 2, 2],
	# 界面 / 结算
	"footstep": [180, 1, 0], "ui_click": [40, 2, 1], "ui_confirm": [60, 1, 2], "ui_back": [60, 1, 2], "card_pick": [80, 1, 2], "chest_open": [300, 1, 2],
	"block_staff": [90, 2, 2], "block_swing": [120, 1, 2], "sp_thrust": [70, 3, 1], "sp_multi": [120, 2, 2], "sp_pierce": [200, 2, 3], "sp_staff_heavy": [150, 2, 2],
	"sp_staff_sweep": [200, 2, 2], "sp_dragon": [400, 1, 4], "bagua_shift": [1500, 1, 4], "bagua_bad": [900, 1, 1], "xiao_note": [800, 1, 3], "bell_ring": [600, 1, 3],
	"peach_petal": [400, 1, 2], "poison_dart": [90, 3, 1],
	"gear_upgrade": [300, 1, 3], "gear_fail": [300, 1, 3], "win_jingle": [2000, 1, 5], "lose_jingle": [2000, 1, 5],
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
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		lim.threshold_db = -4.0
		AudioServer.add_bus_effect(idx, lim)


func play(id: String, pitch_jitter: float = 0.10, vol_db: float = 0.0, pitch_override: float = -1.0) -> void:
	if not enabled or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	var rule: Array = RULES.get(id, [50, 3, 1])
	if now - int(_last_ms.get(id, 0)) < int(rule[0]):
		return
	if _active_count(id) >= int(rule[1]):
		return
	var idx := _borrow_slot(int(rule[2]))
	if idx < 0:
		return
	var p := _players[idx]
	_playing_id[idx] = id
	var vs: Array = _variants.get(id, [])
	p.stream = vs[randi() % vs.size()] if not vs.is_empty() else _streams[id]
	if pitch_override > 0.0:
		p.pitch_scale = pitch_override
	else:
		p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.volume_db = vol_db
	p.play()
	_last_ms[id] = now


func play_skill(skill_id: String, combo_step: int = 0) -> void:
	if skill_id == "dugu" and combo_step > 0:
		play("dugu_flash", 0.04, -1.0, 1.0 + minf(0.28, combo_step * 0.03))
		return
	play(str(SKILL_MAP.get(skill_id, "sw_slash")), 0.10, -2.0)


func play_exp() -> void:
	var now := Time.get_ticks_msec()
	_exp_streak = mini(8, _exp_streak + 1) if now - _exp_last_ms < 400 else 0
	_exp_last_ms = now
	play("pickup_exp", 0.03, -6.0, 1.0 + _exp_streak * 0.03)


func _active_count(id: String) -> int:
	var c := 0
	for i in _players.size():
		if _players[i].playing and _playing_id[i] == id:
			c += 1
	return c


func _borrow_slot(prio: int) -> int:
	var worst := -1
	var worst_prio := prio
	for i in _players.size():
		if not _players[i].playing:
			return i
		var p_id := _playing_id[i]
		var r: Array = RULES.get(p_id, [50, 3, 1])
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
