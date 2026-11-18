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
var orbit_cd := 0.0
var alive := true

# Boss 专用
var is_boss := false
var boss_state := "chase"   # chase | windup | charge
var boss_timer := 0.0
var bolt_timer := 2.0
var charge_dir := Vector2.ZERO
