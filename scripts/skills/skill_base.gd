class_name SkillBase
extends RefCounted
## 攻击技能基类。具体行为在 fist_skills.gd 等文件里继承实现。
## 约定：技能只通过 GameWorld 提供的服务（spawn_proj / area_hit / cone_hit ...）造成影响。

var id := ""
var def: Dictionary = {}
var level := 1
var cd := 0.3
var w: GameWorld


func setup(world: GameWorld, skill_id: String, skill_def: Dictionary) -> void:
	w = world
	id = skill_id
	def = skill_def


## 当前等级的数值（数组按等级取值，标量直接返回）
func p(key: String) -> float:
	return Data.lv(def, key, level)


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


func tick(dt: float) -> void:
	cd -= dt
	if cd <= 0.0:
		if fire():
			cd = p("cooldown") * w.cd_mult()
		else:
			cd = 0.12


## 返回 true 表示成功出手（进入冷却）；false 表示条件不满足（稍后重试）
func fire() -> bool:
	return false


## 玩家受击时调用，返回减免后的伤害（太极劲等防御类技能使用）
func on_hurt(amount: float) -> float:
	return amount


func hit(e: Enemy, base: float, knock_vec: Vector2 = Vector2.ZERO, force_crit: bool = false) -> float:
	return w.hit_enemy(e, base, tags(), knock_vec, id, force_crit)
