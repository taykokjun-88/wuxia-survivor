class_name SkillBase
extends RefCounted
## 攻击技能基类。具体行为在 fist_skills.gd 等文件里继承实现。
## 约定：技能只通过 GameWorld 提供的服务（spawn_proj / area_hit / cone_hit ...）造成影响。
##
## 升级系统：技能没有固定的等级表。每次升级是「一个方向 × 一个档位」（见 Data.directions / Data.tiers），
## 效果累积在 mods 里，p() 取值时自动套用，所以具体技能的行为代码不用关心升级。

const ECHO_MULT := 0.6          # 「增加打击次数」触发的第二次出招的伤害倍率
const ECHO_DELAY := 0.22

var id := ""
var def: Dictionary = {}
var level := 1                   # = 1 + 已升级次数
var cd := 0.3
var cd_total := 0.0              # 本次冷却的总时长（HUD 的冷却转圈用；0 = 没有在冷却）
var w: GameWorld
var upgrades: Array[Dictionary] = []   # [{dir, tier}]
var mods: Dictionary = {
	"damage": 0.0, "cooldown": 0.0, "range": 0.0, "targets": 0.0, "buff": 0.0,
	"debuff": 0.0, "duration": 0.0, "heal": 0.0, "hits": 0.0, "crit": 0.0, "empower": 0.0,
	"block": 0.0, "pierce_def": 0.0, "stun": 0.0, "vuln": 0.0, "crit_dmg": 0.0,          # 杨家将的方向：铁壁 / 贯穿 / 定身 / 破绽
}
var echoing := false
var empowered := false           # 本次出手是否催动（盈境 + 内力够）
var echo_t := -1.0
var link_applied: Dictionary = {}   # 心法「同修」联动：已经加进 mods 的数值（重算时只补差值）
var link_flags: Dictionary = {}     # 联动里的特殊效果：ying / neili_hit / vuln / bleed
var free_cast := false           # 免费释放（号令天下）：不涨刀魂、不进冷却


func setup(world: GameWorld, skill_id: String, skill_def: Dictionary) -> void:
	w = world
	id = skill_id
	def = skill_def
	# 招式自带的特色（数据表里的 *_base）：暴击 / 减速 / 连击等从第 1 层就有
	mods["crit"] += float(def.get("crit_base", 0.0))
	mods["debuff"] += float(def.get("slow_base", 0.0))
	mods["hits"] += float(def.get("echo_base", 0.0))


## 心法联动：把本次重算的联动数值同步进 mods（和升级加成叠加，不会重复累加）
func apply_link(link: Dictionary, flags: Dictionary) -> void:
	for k in mods:
		var want := float(link.get(k, 0.0))
		var had := float(link_applied.get(k, 0.0))
		if not is_equal_approx(want, had):
			mods[k] = float(mods[k]) + (want - had)
			link_applied[k] = want
	link_flags = flags


## 当前数值 = Lv1 基础值 × 升级方向加成
func p(key: String) -> float:
	var v := Data.lv(def, key, 1)
	if key == "damage":
		v *= 1.0 + float(mods["damage"])
		if echoing:
			v *= ECHO_MULT
	elif key == "cooldown":
		if not bool(def.get("fixed_cd", false)):          # 无名枪法：冷却固定，不能缩短
			v *= maxf(0.35, 1.0 - float(mods["cooldown"]))
	var m: Dictionary = def["map"]
	if (m["range"] as Array).has(key):
		v *= 1.0 + float(mods["range"])
	if (m["duration"] as Array).has(key):
		v *= 1.0 + float(mods["duration"])
	if str(m["targets"]) == key:
		v += float(mods["targets"])
	return v


## 催动消耗的内力（运功升级可降低，最多 −70%）
func empower_cost() -> float:
	return float(def.get("empower_cost", 8.0)) * Data.T("empower_cost_mult") * maxf(0.25, 1.0 - float(mods["empower"]) - w.st("empower_cut"))


## HUD 冷却转圈：还剩多少比例（1 = 刚出手，0 = 可以再出手）和剩余秒数
func cd_frac() -> float:
	if cd_total <= 0.2 or cd <= 0.0:
		return 0.0
	return clampf(cd / cd_total, 0.0, 1.0)


func cd_secs() -> float:
	return maxf(0.0, cd) if cd_total > 0.2 else 0.0


## 招式专属特效 id（data 里 skills.<id>.fx：slash / ring / proj / muzzle / arrive / impact / bell）；没有素材时返回 ""，调用方继续用程序绘制
func fxid(kind: String) -> String:
	var f: Variant = def.get("fx", {})
	var id := str((f as Dictionary).get(kind, "")) if f is Dictionary else ""
	return id if id != "" and w != null and w.vfx.has(id) else ""


func tags() -> Array:
	return def["tags"]


## 该技能是否装备了本局唯一的专属强化
func enhanced() -> bool:
	return w.enhance_id == id


## 专属强化等级（未强化为 0，最高 3）
func elv() -> int:
	return w.enhance_level if enhanced() else 0


## 按强化等级取值：Lv1 / Lv2 / Lv3
func ev(a: float, b: float, c: float) -> float:
	match elv():
		1: return a
		2: return b
	return c


# ---------------------------------------------------------------------
# 升级方向
# ---------------------------------------------------------------------

## 该技能可以抽到的升级方向
func available_dirs() -> Array[String]:
	var out: Array[String] = []
	var m: Dictionary = def["map"]
	var banned: Array = def.get("no_dirs", [])
	var only: Array = def.get("only_dirs", [])
	for dir in Data.directions:
		if banned.has(dir):
			continue
		if not only.is_empty() and not only.has(dir):         # 只允许特定方向的招式（无名枪法：暴击 / 连击 / 贯穿 / 定身 / 破绽）
			continue
		if bool(Data.directions[dir].get("only", false)) and only.is_empty() and not (dir == "iron" and str(def.get("school", "")) == "spear"):
			continue                                          # 专属方向：铁壁只给杨家将的招式，其余只给指定了 only_dirs 的招式
		if dir == "range" and (m["range"] as Array).is_empty():
			continue
		if dir == "duration" and (m["duration"] as Array).is_empty():
			continue
		if dir == "targets" and str(m["targets"]) == "":
			continue
		out.append(dir)
	return out


## 「增加目标」对不同技能的实际加成：穿透 +n；弹体数量 +ceil(n/2)
func target_gain(n: float) -> float:
	return n if str(def["map"]["targets"]) == "pierce" else ceilf(n / 2.0)


func add_upgrade(dir: String, tier: int) -> void:
	var v := float(Data.directions[dir]["values"][tier])
	upgrades.append({"dir": dir, "tier": tier})
	level = 1 + upgrades.size()
	match dir:
		"damage": mods["damage"] += v / 100.0
		"cooldown": mods["cooldown"] = minf(0.6, float(mods["cooldown"]) + v / 100.0)
		"range": mods["range"] += v / 100.0
		"targets": mods["targets"] += target_gain(v)
		"buff": mods["buff"] += v
		"debuff": mods["debuff"] = minf(0.6, float(mods["debuff"]) + v / 100.0)
		"duration": mods["duration"] += v / 100.0
		"heal": mods["heal"] += v / 100.0
		"hits": mods["hits"] = minf(0.8, float(mods["hits"]) + v / 100.0)
		"crit": mods["crit"] += v / 100.0
		"empower": mods["empower"] = minf(0.7, float(mods["empower"]) + v / 100.0)
		"iron": mods["block"] += v / 100.0
		"pierce_def": mods["pierce_def"] += v / 100.0
		"stun": mods["stun"] += v / 100.0
		"vuln": mods["vuln"] += v / 100.0
		"crit_dmg": mods["crit_dmg"] += v / 100.0


## 升级卡片上的效果文字
func upgrade_text(dir: String, tier: int) -> String:
	var d: Dictionary = Data.directions[dir]
	var v := float(d["values"][tier])
	var n := target_gain(v)
	return str(d["fmt"]).replace("{v}", Data._fmt(v)).replace("{n}", Data._fmt(n))


# ---------------------------------------------------------------------
# 出招
# ---------------------------------------------------------------------

func tick(dt: float) -> void:
	if echo_t >= 0.0:
		echo_t -= dt
		if echo_t < 0.0:
			echoing = true
			fire()
			echoing = false
	cd -= dt
	if cd <= 0.0:
		empowered = w.can_empower(empower_cost())
		var yuan: bool = w.yuanman_ready and str(def.get("school", "")) == "fist"     # 天赋「盈而圆满」：这一次出手免费催动 + 必暴击
		if yuan:
			empowered = true
		var bd := w.baodao_try(self)         # 刀魂满：这一次出手是「霸刀破岳」
		if fire():
			Sfx.play_skill(id)
			if yuan:
				w.yuanman_ready = false
				w.yuanman_cd = [8.0, 6.0, 4.0][clampi(int(w.st("t_yuanman")), 1, 3) - 1]
				w.force_crit_t = 0.3
			elif empowered:
				w.pay_empower(empower_cost())
			cd = p("cooldown") * w.cd_mult()
			cd_total = cd
			_after_fire()
			w.fist_after_cast(self)
			if bd:
				w.baodao_done()
		else:
			cd = 0.12
			cd_total = 0.0        # 只是在等目标出现，不算冷却
		w.baodao = false
		empowered = false


func _after_fire() -> void:
	if def.has("anim"):
		w.play_anim(str(def["anim"]), 0.3)
	if float(mods["buff"]) > 0.0:
		w.add_neili(float(mods["buff"]))
	if float(mods["hits"]) > 0.0 and w.rng.randf() < float(mods["hits"]):
		echo_t = ECHO_DELAY


## 返回 true 表示成功出手（进入冷却）；false 表示条件不满足（稍后重试）
func fire() -> bool:
	return false


## 命中前的额外伤害倍率 / 必暴击 / 对护盾的伤害倍率（刀客的招式按目标状态改写）
func hit_mult(_e: Enemy) -> float:
	return 1.0


func hit_crit(_e: Enemy) -> bool:
	return false


## 无视目标防御的比例（无名枪法）
func ignore_def() -> float:
	return 0.0


## HUD 上显示的招式名（无名枪法带等级）
func display_name() -> String:
	return str(def["name"])


func shield_mult() -> float:
	return 1.0


## 真气爆发 / 霸刀破岳时调用（斩蛟沉海刀「号令天下」使用）
func on_burst() -> void:
	pass


func on_baodao() -> void:
	pass


## 玩家受击时调用，返回减免后的伤害（回澜卸力诀等防御类技能使用）
func on_hurt(amount: float) -> float:
	return amount


func hit(e: Enemy, base: float, knock_vec: Vector2 = Vector2.ZERO, force_crit: bool = false) -> float:
	return w.hit_enemy(e, base, tags(), knock_vec, id, force_crit)
