class_name Projectile
extends RefCounted
## 弹体：玩家的掌风/剑气/掌印，以及 Boss 的敌方弹幕（hostile）。
## damage 是未乘加成的基础伤害，命中时才结算（心法标签加成、内力、暴击）。

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var speed := 0.0
var radius := 10.0
var damage := 10.0
var pierce := 1
var life := 1.0
var kind := "bolt"      # wave | bolt | palm | finger
var knock := 0.0
var hostile := false
var cuttable := false     # 敌方普通投射物（弓箭 / 小剑气）：无迹九变剑可以斩落；Boss 大招不行
var angle := 0.0
var hit := {}           # 已命中敌人 uid，避免同一弹体重复伤害

var vfx_id := ""         # 这个招式专属的弹体特效（没有则按 kind 取通用的）
var skill_id := ""
var tags: Array = []

# 特殊机制
var homing := false
var turn := 0.0
var target: Enemy = null
var split := 0          # >0：首次命中后分裂成两道小弹体
var boomerang := false
var returning := false
var stun := 0.0
var splash := 0.0        # 命中后的小范围溅射半径（0 = 没有）
var splash_frac := 0.0   # 溅射伤害占本次伤害的比例
var falloff := 1.0       # 每穿透一个目标，后续伤害乘以这个系数
var stun_chance := 1.0   # 命中时定身的几率
var chain := false
var bounce := 0         # 折锋变：剩余弹射次数（穿透耗尽后转向另一名敌人，与穿透同时生效）
var bounce_dmg := 0.5
var pierce_reset := 1    # 弹射后恢复的穿透数
var poison := 0.0        # 命中叠加的毒层（每秒伤害）
var vuln := 0.0          # 命中前先令敌人露出破绽（万法皆破）
var empowered := false   # 催动版出手的弹体（对 Boss 罡气 ×3）
var baodao := false       # 霸刀破岳出手的弹体（命中时按破岳结算）
var bleed := 0.0         # 命中叠加的撕裂层数
var slowv := 0.0         # 命中减速比例
