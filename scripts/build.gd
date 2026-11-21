class_name Build
extends RefCounted
## 把局外成长（属性点 + 天赋 + 装备）合成一份加成，交给 GameWorld。开局前调用一次。


static func equipped_items(equip: Dictionary, school_id: String) -> Array:
	var out := []
	for slot in Gear.slot_ids():
		if equip.has(slot):
			var it := Gear.make(str(equip[slot]), school_id, Save.enh_level(str(equip[slot])))
			if not it.is_empty():
				out.append(it)
	return out


static func merge(into: Dictionary, add: Dictionary) -> void:
	for k in add:
		into[k] = float(into.get(k, 0.0)) + float(add[k])


static func apply_to(world: GameWorld, alloc: Dictionary, talents: Dictionary, equip: Dictionary, school_id: String) -> void:
	var stats := Meta.stats_for(alloc)
	var tsplit := Talents.split_skill_mods(Talents.stats_for(talents, school_id))
	merge(stats, tsplit[0])
	var gb := Gear.bonuses(equipped_items(equip, school_id))
	merge(stats, gb["stats"])
	world.meta_alloc = Meta.clean_alloc(alloc)
	world.talent_stats = stats
	world.tulong_equipped = false
	for it in equipped_items(equip, school_id):
		if str(it["slot"]) == "weapon" and str(it["name"]).begins_with("屠龙宝刀"):
			world.tulong_equipped = true
	world.talent_skill_mods = tsplit[1]
	world.gear_skill_mods = gb["skill_mods"]
	world.gear_xinfa = gb["xinfa"]
