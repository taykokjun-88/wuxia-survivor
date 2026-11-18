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

# 精英 / Boss
var is_elite := false
var is_boss := false
var is_final := false
var boss_name := ""
var boss_bolts := 14
var boss_state := "chase"   # chase | windup | charge
var boss_timer := 0.0
var bolt_timer := 2.0
var charge_dir := Vector2.ZERO
