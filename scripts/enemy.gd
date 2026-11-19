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
var chain := false       # 被"连锁"点穴：死亡时爆炸
var vuln := 0.0          # 破绽：受到的伤害额外 +vuln
var vuln_t := 0.0
var poison_dps := 0.0    # 中毒（金蛇剑法）：每秒伤害，层数叠加
var poison_t := 0.0
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
var boss_bolts := 14
var boss_state := "chase"   # chase | windup | charge
var boss_timer := 0.0
var bolt_timer := 2.0
var charge_dir := Vector2.ZERO
