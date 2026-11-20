class_name Enemy
extends RefCounted
## 轻量敌人数据（不使用 Node，便于同屏上千敌人）。

var uid := 0
var type_id := ""
var pos := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var speed := 60.0
var damage := 5.0
var radius := 12.0
var exp_value := 1
var color := Color.WHITE
var knock := Vector2.ZERO
var flash := 0.0
var alive := true

# 状态
var stun := 0.0          # 定身/击晕剩余时间
var slow_t := 0.0        # 减速剩余时间
var slow_mult := 1.0
var is_prop := false       # 可破坏的场景物件（木箱 / 酒坛 / 火盆）：不动、不伤人，打碎掉东西
var chain := false       # 被"连锁"点穴：死亡时爆炸
var vuln := 0.0          # 破绽：受到的伤害额外 +vuln
var vuln_t := 0.0
var atk_down := 0.0       # 破绽附带：攻击力降低（万法皆破）
var atk_down_t := 0.0
var poison_dps := 0.0    # 中毒（金蛇剑法）：每秒伤害，层数叠加
var poison_t := 0.0
var bleed_stacks := 0     # 撕裂（刀客）：层数 / 每秒伤害 / 剩余时间；每层降低目标防御
var bleed_dps := 0.0
var bleed_t := 0.0
var bleed_acc := 0.0
var burn_t := 0.0         # 燃木刀法：被火海灼烧中（死亡时可爆炸）
var burn_burst := 0.0
var burn_dmg := 0.0
var poison_acc := 0.0
var poison_burst := 0.0  # >0：死亡时毒雾爆开的半径
var weak_fx := 0.0       # 「破绽」提示的冷却（避免飘字刷屏）

# 精英 / Boss
var is_elite := false
var is_boss := false
var is_final := false
var born := 0.0           # 出生时间（统计 Boss 击杀耗时）
var boss_name := ""
var guard := 0.0          # Boss 护体罡气：期间只受部分伤害；被打破后进入虚弱
var guard_max := 0.0
var weak_t := 0.0         # 罡气被破后的虚弱剩余时间（受伤加成）
var guard_regen := 0.0    # 虚弱结束后，罡气重新凝聚的倒计时
var defense := 0.0          # 受到的伤害 ×(1 − 防御 ×(1 − 玩家无视防御比例))
var shield := 0.0           # 护盾：先于血量吃伤害（破防时 ×2）
var shield_max := 0.0
var phase2_def: Dictionary = {}
var phase2 := false
var invuln_t := 0.0
var cast_list: Array = []   # 多点技能（掌印 / 剑雨）的落点
var skills: Array = []      # Boss 技能列表（见 data.boss_skills）
var skills2: Array = []     # 血量低于 phase_hp 后追加的技能
var phase_hp := 0.0
var skill_idx := 0
var skill_gap := 2.5
var cast_id := ""           # 正在施放（含预警）的技能
var cast_t := 0.0
var cast_dur := 0.0
var cast_dir := Vector2.ZERO
var cast_pos := Vector2.ZERO
var cast_start := Vector2.ZERO
var cast_stage := 0
var rage_t := 0.0
var shield_t := 8.0
var summon_cd := 6.0
var mskill := ""            # 杂兵行为用的技能 id
var touch_slow := 0.0       # 碰到玩家时的减速时长
var behavior := ""          # 杂兵行为：archer 远程 / charger 冲锋
var art_key := ""
var tint := Color.WHITE
var boss_bolts := 14
var boss_state := "chase"   # chase | windup | charge
var boss_timer := 0.0
var bolt_timer := 2.0
var charge_dir := Vector2.ZERO


## 攻击力倍率（被破绽削弱时 < 1）
func atk_mul() -> float:
	return 1.0 - atk_down if atk_down_t > 0.0 else 1.0
