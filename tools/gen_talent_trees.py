#!/usr/bin/env python3
"""生成 data/talent_trees.json（按流派的 RO 式天赋树）。目前只有武者（fist）；设计见 docs/talent_fist_draft.md 第三版。
改天赋内容 → 改这里 → 运行 python3 tools/gen_talent_trees.py → python3 tools/sync_talents.py"""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
GATES = [0, 4, 8, 12, 16, 20, 26, 36]       # 第 1~8 层所需的「本系已投入点数」
ONE, FULL = "one", "full"


def N(id, name, mx, tier, col, row, stat, desc, req=None, cap=False, peak=False):
    return {"id": id, "name": name, "max": mx, "tier": tier, "col": col, "row": row, "stat": stat, "desc": desc,
            "req": req or [], "cap": cap, "peak": peak}


def chain(prefix, col, tiers, rows, specs):
    """招式链：4 个节点；n1→n2 前置 ≥1 点；n2→n3、n3→终极 前置点满"""
    out = []
    for i, (nm, mx, stat, desc) in enumerate(specs):
        nid = f"{prefix}_{i + 1}"
        req = [] if i == 0 else [[f"{prefix}_{i}", ONE if i == 1 else FULL]]
        out.append(N(nid, nm, mx, tiers[i], col, rows[i], stat, desc, req, cap=(i == 3)))
    return out


def generic(prefix, specs, tiers, rows, modes):
    out = []
    for i, (nm, mx, stat, desc) in enumerate(specs):
        req = [] if i == 0 else [[f"{prefix}_{i}", modes[i]]]
        out.append(N(f"{prefix}_{i + 1}", nm, mx, tiers[i], 3, rows[i], stat, desc, req, cap=(tiers is SIG_TIERS and i == len(specs) - 1)))
    return out


GEN_TIERS = [1, 2, 4, 6, 7, 7]
GEN_ROWS = [1, 2, 4, 6, 7, 8]
GEN_MODES = [None, ONE, ONE, FULL, ONE, FULL]
SIG_TIERS = [1, 2, 3, 4, 5, 6, 7, 7]          # 招牌系统链：8 个节点
SIG_ROWS = [1, 2, 3, 4, 5, 6, 7, 8]
SIG_MODES = [None, ONE, ONE, FULL, ONE, ONE, FULL, FULL]
A_T, A_R = [1, 3, 5, 7], [1, 3, 5, 7]
B_T, B_R = [2, 4, 6, 7], [2, 4, 6, 7]

gang = (
    chain("fg_a", 0, A_T, A_R, [
        ("连山不绝", 3, {"t_lianshan": 1}, "连山贯日拳连续命中同一敌人，每次叠 1 层「破绽」，该敌人受此招伤害 +5%/层；层数上限 3/4/5"),
        ("贯日之势", 3, {"t_guanri": 1}, "第三拳击退 +20%/级；被击飞的敌人撞上其他敌人，对周围敌人造成此招 25%/级 的冲撞伤害"),
        ("横扫余劲", 2, {"t_hengsao": 1}, "强化「横扫千军」后，第三拳追加一道余劲扇面，伤害 40%/70%"),
        ("贯日破天", 1, {"t_guanri_cap": 1}, "终极：连山贯日拳第三拳变成贯穿直线的「贯日一击」，直线上所有敌人受 200% 伤害并防御 −30%（3 秒）")]) +
    chain("fg_b", 1, B_T, B_R, [
        ("沉岳蓄势", 3, {"t_chenyue": 1}, "沉岳铁拳「内力越满伤害越高」的上限 +10%/级"),
        ("金刚震地", 3, {"t_jingang": 1}, "沉岳铁拳命中后在目标处爆出冲击波，造成 20%/30%/40% 伤害（小范围）"),
        ("不坏金身", 2, {"t_bupo": 1}, "沉岳铁拳出拳后 2 秒内受到伤害 −8%/−15%"),
        ("沉岳崩山", 1, {"t_chenyue_cap": 1}, "终极：内力 ≥90% 时沉岳铁拳必暴击，并震晕周围敌人 1.2 秒")]) +
    chain("fg_c", 2, B_T, B_R, [
        ("地脉绵延", 3, {"skill:quake_fist:range": 0.08, "skill:quake_fist:duration": 0.1}, "裂脉震拳范围 +8%/级，击晕时间 +10%/级"),
        ("裂脉连震", 3, {"t_liemai": 1}, "裂脉震拳落点 0.5 秒后再震一次，伤害 30%/45%/60%"),
        ("震断筋骨", 2, {"t_zhenduan": 1}, "被击晕的敌人受到的所有伤害 +8%/级（易伤）"),
        ("裂脉断岳", 1, {"t_liemai_cap": 1}, "终极：裂脉震拳落点留下裂缝区域 3 秒，区域内敌人持续受伤并减速 40%")]) +
    generic("fg_g", [
        ("刚劲", 3, {"damage_pct": 0.02}, "招式伤害 +2%/级"),
        ("蓄劲", 3, {"qi_gain": 0.15, "t_xujin": 1}, "出拳掌攒劲速度 +15%/级；暴击时多攒 1 点劲/级"),
        ("余震劲", 3, {"t_yuzhenjin": 1}, "寸劲震爆 0.6 秒后原地再震一次（30%/50%/70%）"),
        ("破阵劲", 3, {"t_pozhen": 1}, "震爆命中的敌人防御 −10%/级（3 秒），对 Boss 罡气额外 +10%/级"),
        ("破军", 4, {"crit_mult": 0.1}, "暴击伤害 +10%/级"),
        ("透骨劲", 3, {"t_tougu": 1}, "震爆的冲击波穿体，在目标背后炸开扇形冲击（15%/级）"),
        ("连环劲", 2, {"t_lianhuan": 1}, "震爆后有 12%/24% 几率保留一半的劲"),
        ("寸劲无双", 1, {"t_wushuang": 1}, "终极：震爆只需攒到 70 劲，范围 +30%")], SIG_TIERS, SIG_ROWS, SIG_MODES))
gang.append(N("fg_peak", "阳刚护体", 1, 8, 1.5, 9, {"burst_yang": 1},
              "巅峰：阳性内力（双阳）：回内力 +50%；内力满时生成护盾（上限 50% 气血），护盾在时反弹所受伤害的 30%", peak=True))

rou = (
    chain("fr_a", 0, A_T, A_R, [
        ("一阳连点", 3, {"skill:point_finger:targets": 1.0}, "凝霜点指每次多射 1 道指劲（+1/级）"),
        ("寒霜入骨", 3, {"t_hanshuang": 1}, "指劲每穿透一个目标的伤害衰减 −10%/级；命中定身几率 +5%/级"),
        ("霜痕蔓延", 2, {"t_shuanghen": 1}, "被定身的敌人死亡时炸出冰晶，使 120 范围内敌人减速 30%/50%（2 秒）"),
        ("万籁俱寂", 1, {"t_wanlai": 1}, "终极：被定身的敌人受到凝霜点指伤害 ×2，定身时间 +1 秒")]) +
    chain("fr_b", 1, B_T, B_R, [
        ("落英缤纷", 3, {"skill:whirl_palm:range": 0.12}, "乱花拂柳掌范围 +12%/级"),
        ("花开不败", 3, {"t_huakai": 1}, "乱花拂柳掌连发圈数上限 +1/级（3 → 6 圈）"),
        ("拂柳回气", 2, {"t_fuliu": 1}, "乱花拂柳掌一圈命中 ≥3 个敌人时回内力 2/4 点（每秒最多一次）"),
        ("乱花漫天", 1, {"t_luanhua": 1}, "终极：乱花拂柳掌三圈满时追加一圈全屏击退，并回复 5% 气血")]) +
    chain("fr_c", 2, B_T, B_R, [
        ("卸力归元", 3, {"t_xieli": 1}, "回澜卸力诀化解比例 +5%/级"),
        ("回澜反震", 3, {"t_fanzhen": 1}, "反击伤害 +20%/级，反击额外击退"),
        ("太极圆转", 2, {"t_yuanzhuan": 1}, "化解伤害后 3 秒内移速 +10%/20%，并有 10%/20% 几率清零回澜卸力诀的冷却"),
        ("回澜归海", 1, {"t_huigui": 1}, "终极：累计化解 100 点伤害后释放一次范围反震，伤害 = 已化解量的 150%")]) +
    generic("fr_g", [
        ("调息", 3, {"hp_regen": 0.3}, "气血回复 +0.3/秒每级"),
        ("虚境回气", 3, {"t_xuhui": 1}, "虚境（内力 <25%）回内力 +25%/级"),
        ("盈境绵长", 3, {"ying_shift": -0.05}, "盈境门槛从 65% 降到 60% / 55% / 50%"),
        ("盈而圆满", 3, {"t_yuanman": 1}, "盈境持续满 3 秒进入「圆满」：下一次出手必暴击并免费催动（冷却 8/6/4 秒）"),
        ("绵里藏针", 4, {"armor": 0.4}, "防御 +0.4/级"),
        ("入定归元", 3, {"t_rudin": 1, "med_regen": 0.5}, "入定回内力更快；入定被打断时释放气浪击退周围敌人"),
        ("虚中生盈", 2, {"t_xusheng": 1}, "从虚境升到盈境时，立刻清零全部招式剩余冷却的 8%/16%"),
        ("气海翻涌", 1, {"t_qihai": 1}, "终极：每次由平境升入盈境，震出一圈气浪（伤害 100%）并把全部招式冷却缩短 1 秒（每 8 秒一次）")], SIG_TIERS, SIG_ROWS, SIG_MODES))
rou.append(N("fr_peak", "阴柔回春", 1, 8, 1.5, 9, {"burst_yin": 1},
             "巅峰：阴性内力（双阴）：真气爆发时额外回血，并获得 8 秒攻速 +30%", peak=True))

ling = (
    chain("fl_a", 0, A_T, A_R, [
        ("六阳初开", 2, {"skill:cloud_palm:targets": 1.0}, "朔雪融阳掌初始掌印 +1/级"),
        ("融雪成阳", 3, {"skill:cloud_palm:range": 0.15, "skill:cloud_palm:debuff": 0.1}, "掌印溅射范围 +15%/级，减速效果 +10%/级"),
        ("阳回雪归", 3, {"t_yanghui": 1}, "掌印击杀敌人后，下一枚掌印伤害 +30%/级（最多叠 3 层）"),
        ("阳极生阴", 1, {"t_yangji": 1}, "终极：掌印齐备时每 5 秒融合成一枚巨掌印，穿透、范围、伤害各 ×2")]) +
    chain("fl_b", 1, B_T, B_R, [
        ("龙吟九天", 3, {"skill:yue_palm:targets": 1.0}, "撼岳惊涛掌贯穿 +1/级"),
        ("惊涛叠浪", 3, {"t_jingtao": 1}, "撼岳惊涛掌飞到尽头时炸成一圈浪，造成 30%/50%/70% 伤害并击退"),
        ("撼岳之势", 2, {"t_hanyue": 1}, "撼岳惊涛掌每穿透一个敌人，伤害反而 +5%/10%（递增而非衰减）"),
        ("惊涛骇浪", 1, {"t_jingtao_cap": 1}, "终极：撼岳惊涛掌每第 5 掌改为并排 3 道巨浪")]) +
    chain("fl_c", 2, B_T, B_R, [
        ("四野回响", 3, {"skill:eight_waste:cooldown": 0.1}, "四野归元功冷却 −10%/级"),
        ("八荒并进", 3, {"skill:eight_waste:targets": 2.0}, "四野归元功拳气方向数 +2/级（8 → 14 个）"),
        ("归元返照", 2, {"t_guiyuan": 1}, "四野归元功每道拳气命中敌人时回内力 0.3/0.6 点（每道一次）"),
        ("归元一气", 1, {"t_guiyuan_cap": 1}, "终极：四野归元功的拳气飞到尽头后全部折返汇聚，在身前合成大爆炸（伤害 = 各道拳气总和的 50%）")]) +
    generic("fl_g", [
        ("蓄势待发", 4, {"t_xushi": 1}, "拳掌无敌持续 +1 秒/级（10 → 14 秒）"),
        ("无敌·连珠", 3, {"t_lianzhu": 1}, "无敌期间每次震爆，额外射出 1 道拳气/级"),
        ("真伤加深", 3, {"t_zhenshang": 1}, "无敌期间额外真伤比例 +5%/级（30% → 45%）"),
        ("杀伐还元", 3, {"t_shafa": 1}, "无敌期间每击杀 30/22/15 个敌人，返还 1 次真气爆发次数"),
        ("无敌余威", 3, {"t_yuwei": 1}, "无敌结束后 5 秒内，全部伤害 +8%/级"),
        ("破境余波", 3, {"t_poju": 1}, "无敌结束时震出全屏冲击，伤害 = 无敌期间总伤害的 4%/级"),
        ("气归丹田", 2, {"t_qigui": 1}, "无敌结束时回复 10%/20% 内力"),
        ("无敌金身", 1, {"t_jinshen": 1}, "终极：真气爆发只消耗 50% 内力（无敌结束后返还），无敌期间移速 +30%")], SIG_TIERS, SIG_ROWS, SIG_MODES))
ling.append(N("fl_peak", "调和归元", 1, 8, 1.5, 9, {"burst_harmony": 1},
              "巅峰：调和内力（一阴一阳）：真气爆发次数 ×2（本局可爆发 2 次）", peak=True))

BRANCH = {
    "gang": {"name": "刚", "sub": "近身重击 · 破防 · 击晕", "starter": "chain_fist", "nodes": gang},
    "rou": {"name": "柔", "sub": "控制 · 清场 · 化解反击", "starter": "point_finger", "nodes": rou},
    "ling": {"name": "灵", "sub": "追踪 · 贯穿 · 多向", "starter": "cloud_palm", "nodes": ling},
}
COLS = {"gang": ["连山贯日拳", "沉岳铁拳", "裂脉震拳", "通用"], "rou": ["凝霜点指", "乱花拂柳掌", "回澜卸力诀", "通用"],
        "ling": ["朔雪融阳掌", "撼岳惊涛掌", "四野归元功", "通用"]}

COL_SKILLS = {"gang": ["chain_fist", "vajra_fist", "quake_fist"], "rou": ["point_finger", "whirl_palm", "taiji"], "ling": ["cloud_palm", "yue_palm", "eight_waste"]}
fist = {"gates": GATES, "ji": {"id": "fist_ji", "name": "极意·天人合一", "max": 1, "need": 99, "stat": {"ji_fist": 1.0},
        "desc": "武者之极意：拳掌无敌持续 +5 秒；蓄劲速度翻倍；多 1 次真气爆发；拳掌无敌结束时回复 40% 内力"},
        "branches": {}}
for b, d in BRANCH.items():
    fist["branches"][b] = {"name": d["name"], "sub": d["sub"], "starter": d["starter"], "cols": COLS[b], "col_skills": COL_SKILLS[b], "nodes": d["nodes"]}
    tot = sum(n["max"] for n in d["nodes"])
    assert tot == 50, (b, tot)
(ROOT / "data" / "talent_trees.json").write_text(json.dumps({"fist": fist}, ensure_ascii=False, indent=1), encoding="utf-8")
print("ok, 每系 50 点")
