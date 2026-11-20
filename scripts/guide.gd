class_name Guide
extends RefCounted
## 百晓生的图鉴：玩法 / 招式 / 心法 / 轻功。内容几乎全部由数据表生成，数值改了图鉴自动跟着变。

const CATEGORIES := [["play", "玩法"], ["skill", "招式"], ["xinfa", "心法"], ["qg", "轻功"]]


static func _fmt_page(text: String) -> String:
	var t := text.replace("\\n", "\n")
	var rep := {
		"{ying_at_pct}": str(int(round(Data.T("ying_at") * 100.0))),
		"{ying_dmg_pct}": str(int(round((Data.T("ying_dmg") - 1.0) * 100.0))),
		"{xu_pct}": str(int(round(Data.T("xu_below") * 100.0))),
		"{meditate_after}": "%.1f" % Data.T("meditate_after"),
		"{meditate_reduce_pct}": str(int(round(Data.T("meditate_reduce") * 100.0))),
		"{burst_min_pct}": str(int(round(Data.T("burst_min_frac") * 100.0))),
	}
	for k in rep:
		t = t.replace(k, rep[k])
	return t


## 某个分类的条目：[{title, text, icon_kind, icon_id}]
static func entries(cat: String) -> Array:
	var out: Array = []
	match cat:
		"play":
			for pg in Data.guide["pages"]:
				out.append({"title": pg["title"], "text": _fmt_page(str(pg["text"])), "icon_kind": "", "icon_id": ""})
		"skill":
			for id in Data.skills:
				out.append({"title": Data.skills[id]["name"], "text": skill_text(id), "icon_kind": "skills", "icon_id": id})
		"xinfa":
			for id in Data.xinfa:
				out.append({"title": "%s【%s】" % [Data.xinfa[id]["name"], "阳" if str(Data.xinfa[id].get("yy", "")) == "yang" else "阴"],
					"text": xinfa_text(id), "icon_kind": "xinfa", "icon_id": id})
		"qg":
			for id in Data.qinggong:
				out.append({"title": Data.qinggong[id]["name"], "text": qinggong_text(id), "icon_kind": "", "icon_id": ""})
	return out


static func skill_text(id: String) -> String:
	var d: Dictionary = Data.skills[id]
	var lines: Array = []
	lines.append("【%s】%s" % [Data.tags_text(id), d["desc"]])
	var starter: bool = (Data.schools[str(d["school"])]["starters"] as Array).has(id)
	lines.append("\n获得方式：" + ("可作为起手招式（在驿站出发时 3 选 1），也能在局内升级时领悟。" if starter else "局内升级时，从三张卡里选「领悟」即可学会（一局最多 4 个招式）。"))
	var facts: Array = []
	if d.has("damage"):
		facts.append("基础伤害 %d" % int(Data.lv(d, "damage", 1)))
	if d.has("cooldown"):
		facts.append("冷却 %.1f 秒" % Data.lv(d, "cooldown", 1))
	if d.has("count"):
		facts.append("%s %d" % ["数量", int(Data.lv(d, "count", 1))])
	if d.has("pierce") and float(Data.lv(d, "pierce", 1)) > 1.0:
		facts.append("穿透 %d" % int(Data.lv(d, "pierce", 1)))
	if d.has("reach"):
		facts.append("攻击距离 %d" % int(Data.lv(d, "reach", 1)))
	lines.append("\n基础：" + "　".join(facts))
	var traits: Array = []
	if float(d.get("crit_base", 0.0)) > 0.0:
		traits.append("自带暴击 +%d%%" % int(float(d["crit_base"]) * 100.0))
	if float(d.get("slow_base", 0.0)) > 0.0:
		traits.append("命中减速 %d%%" % int(float(d["slow_base"]) * 100.0))
	if float(d.get("echo_base", 0.0)) > 0.0:
		traits.append("%d%% 几率连续出招" % int(float(d["echo_base"]) * 100.0))
	if float(d.get("splash_radius", 0.0)) > 0.0:
		traits.append("命中后小范围溅射（%d%% 伤害）" % int(float(d.get("splash_frac", 0.0)) * 100.0))
	if float(d.get("stun_chance", 1.0)) < 1.0 and d.has("stun_chance"):
		traits.append("%d%% 几率定身" % int(float(d["stun_chance"]) * 100.0))
	if float(d.get("falloff", 1.0)) < 1.0:
		traits.append("每穿透一个目标伤害衰减 %d%%" % int((1.0 - float(d["falloff"])) * 100.0))
	if not traits.is_empty():
		lines.append("特色：" + "；".join(traits))
	var en: Dictionary = d["enhance"]
	lines.append("\n专属强化「%s」：%s\n　　%s" % [en["name"], en["desc"], en.get("up", "")])
	lines.append("\n催动（盈境自动触发，消耗 %d 内力）：%s" % [int(d.get("empower_cost", 8)), d.get("empower", "")])
	var dirs: Array = []
	var s := SkillBase.new()
	s.setup(null, id, d)
	for dir in s.available_dirs():
		dirs.append(str(Data.directions[dir]["name"]))
	lines.append("\n可抽到的升级方向：" + "、".join(dirs))
	return "\n".join(lines)


static func xinfa_text(id: String) -> String:
	var d: Dictionary = Data.xinfa[id]
	var lines: Array = []
	lines.append("【%s】%s" % [str(d.get("role", "")), "阳性心法" if str(d.get("yy", "")) == "yang" else "阴性心法"])
	lines.append("被动：" + str(d.get("passive", "")))
	lines.append("\n获得方式：局内升级时，从三张卡里选「修习」即可学会（一局最多 2 个心法）；之后每次升级选到它的强化卡，可再强化 %d 次。" % (int(d["max_level"]) - 1))
	lines.append("强化的品质：普通 / 特别 / 优秀 / 传说，每高一档强化量再多 1 份（1 / 2 / 3 / 4 份）；份数越多，被动、标签加成和同修效果越强。")
	var names := {"damage": "伤害", "cooldown": "冷却缩短", "range": "范围", "targets": "目标", "duration": "持续/射程", "crit": "暴击率", "debuff": "命中减速",
		"heal": "命中回血", "hits": "连击几率", "buff": "出招回内力", "empower": "催动消耗减少", "ying": "盈境额外增伤", "neili_hit": "命中回内力", "vuln": "露出破绽", "bleed": "流血几率"}
	var lk: Dictionary = d.get("link", {})
	if not lk.is_empty():
		lines.append("\n同修招式（可以是任何流派的非起手招式，学会后额外加成，每个招式效果不同）：")
		for sid in lk:
			var eff: Array = []
			for k in lk[sid]:
				var v := float(lk[sid][k])
				eff.append(("%s +%d%%" % [names.get(k, k), int(round(v * 100.0))]) if not ["targets", "neili_hit"].has(k) else ("%s" % names.get(k, k) if k == "targets" else "%s %.1f" % [names[k], v]))
			lines.append("  · %s（%s）：%s" % [Data.skills[sid]["name"], Data.skills[sid]["school"] == "fist" and "武者" or (Data.skills[sid]["school"] == "sword" and "剑侠" or "刀客"), "　".join(eff)])
	var per: Array = []
	for k in d["per_level"]:
		var pv := float(d["per_level"][k])
		per.append("%s %s%s" % [Guide.stat_name(str(k)), "+" if pv >= 0.0 else "", str(snappedf(pv, 0.01))])
	lines.append("\n每份强度的被动属性：" + "　".join(per))
	var bonus: Array = []
	for tg in d["bonus"]:
		bonus.append("%s招式 +%d%%" % [tg, int(float(d["bonus"][tg]) * 100.0)])
	lines.append("标签加成：" + "　".join(bonus))
	lines.append("\n内力属性：" + ("阳（两个阳心法 = 纯阳体；一阴一阳 = 调和体）" if str(d.get("yy", "")) == "yang" else "阴（两个阴心法 = 纯阴体；一阴一阳 = 调和体）"))
	var pairs: Array = []
	for h in Data.harmony:
		var pr: Array = h["pair"]
		if pr.has(id):
			var other: String = pr[1] if pr[0] == id else pr[0]
			pairs.append("与「%s」合璧 →「%s」：%s" % [Data.xinfa[other]["name"], h["name"], h["desc"]])
	if not pairs.is_empty():
		lines.append("\n合璧：\n" + "\n".join(pairs))
	return "\n".join(lines)


static func qinggong_text(id: String) -> String:
	var d: Dictionary = Data.qinggong[id]
	var lines: Array = [str(d["desc"])]
	lines.append("\n获得方式：每局出发前在驿站选择（6 选 1）。")
	lines.append("冲刺消耗 %d 内力，冷却 %.1f 秒%s。" % [int(d["cost"]), float(d["cd"]), "，可连续冲刺 %d 次" % int(d["charges"]) if int(d.get("charges", 1)) > 1 else ""])
	return "\n".join(lines)


static func stat_name(k: String) -> String:
	var names := {"max_neili": "内力上限", "neili_regen": "内力回复", "full_hp_regen": "内力满时回血", "ying_shift": "盈境门槛", "max_hp": "气血", "block_chance": "格挡几率",
		"kill_neili": "击杀回内力", "hit_slow": "命中减速", "thorns": "反震", "cd_reduce": "冷却缩减", "hp_regen": "气血回复", "pickup_heal": "拾取回血",
		"shield_max": "护盾上限", "shield_regen": "护盾回复", "crit_chance": "暴击率", "crit_mult": "暴击伤害", "exp_pct": "经验获取", "pickup_range": "拾取范围"}
	return str(names.get(k, k))
