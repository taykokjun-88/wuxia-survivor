class_name Projectile
extends RefCounted
## 弹体：玩家的掌风/剑气，以及 Boss 的敌方弹幕（hostile）。

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var radius := 10.0
var damage := 10.0
var pierce := 1
var life := 1.0
var kind := "bolt"      # wave | bolt
var knock := 0.0
var hostile := false
var angle := 0.0
var hit := {}           # 已命中敌人 uid，避免同一弹体重复伤害
