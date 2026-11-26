#!/usr/bin/env python3
"""生成 data/talent_trees.json（按流派的 RO 式天赋树）。目前只有武者（fist）；设计见 docs/talent_fist_draft.md 第三版。
改天赋内容 → 改这里 → 运行 python3 tools/gen_talent_trees.py → python3 tools/sync_talents.py"""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
GATES = [0, 3, 6, 9, 15, 21, 25, 36]       # 第 1~8 层所需的「本系其余节点已投入点数」（你定的：3 / 6 / 9 / 15 / 21 / 25 / 36）
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
        ("寸劲无双", 1, {"t_wushuang": 1}, "终极：震爆只需攒到 90 劲，范围 +15%")], SIG_TIERS, SIG_ROWS, SIG_MODES))
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
        ("蓄势待发", 4, {"t_xushi": 1}, "拳掌无敌持续 +1 秒/级（6 → 10 秒）"),
        ("无敌·连珠", 3, {"t_lianzhu": 1}, "无敌期间每次震爆，额外射出 1 道拳气/级"),
        ("真伤加深", 3, {"t_zhenshang": 1}, "无敌期间额外真伤比例 +5%/级（20% → 35%）"),
        ("杀伐还元", 3, {"t_shafa": 1}, "无敌期间每击杀 30/22/15 个敌人，返还 1 次真气爆发次数"),
        ("无敌余威", 3, {"t_yuwei": 1}, "无敌结束后 5 秒内，全部伤害 +8%/级"),
        ("破境余波", 3, {"t_poju": 1}, "无敌结束时震出全屏冲击，伤害 = 无敌期间总伤害的 2%/级"),
        ("气归丹田", 2, {"t_qigui": 1}, "无敌结束时回复 10%/20% 内力"),
        ("无敌金身", 1, {"t_jinshen": 1}, "终极：真气爆发只消耗 50% 内力（无敌结束后返还），无敌期间移速 +30%")], SIG_TIERS, SIG_ROWS, SIG_MODES))
ling.append(N("fl_peak", "调和归元", 1, 8, 1.5, 9, {"burst_harmony": 1},
              "巅峰：调和内力（一阴一阳）：真气爆发次数 ×2（本局可爆发 2 次）", peak=True))


# ======================= 剑客 =======================
def chainN(prefix, col, tiers, rows, modes, specs, cap_last=True):
    out = []
    for i, (nm, mx, stat, desc) in enumerate(specs):
        req = [] if i == 0 else [[f"{prefix}_{i}", modes[i]]]
        out.append(N(f"{prefix}_{i + 1}", nm, mx, tiers[i], col, rows[i], stat, desc, req, cap=(cap_last and i == len(specs) - 1)))
    return out


SK_GEN = GEN_TIERS
sw_gang = (
    chain("sg_a", 0, A_T, A_R, [
        ("劲柏扎根", 3, {"skill:qingsong:damage": 0.08}, "劲柏凌霜剑伤害 +8%/级"),
        ("松涛连绵", 3, {"skill:qingsong:range": 0.10, "skill:qingsong:cooldown": 0.03}, "范围 +10%/级、冷却 −3%/级"),
        ("劲柏不折", 2, {"t_jinbo": 1}, "每第 3 次刺击必暴击，剑锋加长 15%/30%"),
        ("松涛万籁", 1, {"t_songtao": 1}, "终极：松涛每多扫到 1 个敌人，此招伤害 +10%（最多 +80%）；松涛不再需要前方 ≥2 个敌人")]) +
    chain("sg_b", 1, B_T, B_R, [
        ("无锋大巧", 3, {"skill:zhongjian:damage": 0.10}, "沉渊重剑伤害 +10%/级"),
        ("重剑之势", 3, {"skill:zhongjian:range": 0.08}, "范围 +8%/级"),
        ("震地余波", 2, {"t_zhendi": 1}, "重击落地后追加冲击波，伤害 30%/50%"),
        ("沉渊·崩", 1, {"t_chenyuan": 1}, "终极：每第 3 次重击伤害 ×1.8，并击晕周围敌人 1.5 秒")]) +
    chain("sg_c", 2, B_T, B_R, [
        ("断云", 3, {"skill:yitian:damage": 0.08}, "断云裂帛剑伤害 +8%/级"),
        ("裂帛", 3, {"skill:yitian:range": 0.10}, "范围 +10%/级"),
        ("云开见日", 2, {"t_yunkai": 1}, "剑光命中的敌人防御 −15%/−25%（3 秒）"),
        ("斩云·极", 1, {"t_zhanyun": 1}, "终极：剑光击杀敌人时，在该处再斩出一道追击剑气（伤害 60%）")]) +
    generic("sg_g", [
        ("刚劲", 3, {"damage_pct": 0.02}, "招式伤害 +2%/级"),
        ("连段", 3, {"t_liandan": 1}, "近战招式每次出手有 10%/20%/30% 几率多打一段（伤害 60%）"),
        ("隔山打牛", 4, {"t_geshan": 1}, "近战招式命中后，在目标身后炸开小扇形冲击（伤害 12%/级）"),
        ("余震", 3, {"t_yuzhen": 1}, "范围招式 0.6 秒后原地再震一次（伤害 20%/35%/50%）"),
        ("破军", 4, {"crit_mult": 0.1}, "暴击伤害 +10%/级"),
        ("无坚不摧", 5, {"damage_pct": 0.03}, "招式伤害 +3%/级")], GEN_TIERS, GEN_ROWS, GEN_MODES))
sw_gang.append(N("sg_peak", "剑意凌霄", 1, 8, 1.5, 9, {"burst_yang": 1, "ying_dmg": 0.1},
                 "巅峰：阳性内力（回内力 +50%、满内力护盾并反弹 30%），盈境伤害 +10%", peak=True))

sw_rou = (
    chain("sr_a", 0, A_T, A_R, [
        ("快剑精进", 3, {"skill:kuang_feng:damage": 0.06}, "猎风疾影剑伤害 +6%/级"),
        ("快剑如风", 3, {"skill:kuang_feng:cooldown": 0.08}, "冷却 −8%/级"),
        ("四剑成风", 2, {"t_sijian": 1}, "每第 4 剑的剑风多 1/2 道，伤害 +30%/60%"),
        ("疾风骤雨", 1, {"t_jifeng": 1}, "终极：每第 8 剑变成 360° 风暴，伤害 ×2.5")]) +
    chain("sr_b", 1, B_T, B_R, [
        ("圆转", 3, {"skill:taiji_sword:range": 0.12}, "圆转绵剑剑圈范围 +12%/级"),
        ("绵绵不绝", 3, {"skill:taiji_sword:damage": 0.08}, "伤害 +8%/级"),
        ("回敬", 2, {"t_huijing": 1}, "被打回的敌方弹幕伤害 +50%/+100%"),
        ("太极无极", 1, {"t_taijiwu": 1}, "终极：每打回 5 发弹幕，释放一圈全屏反震")]) +
    chain("sr_c", 2, B_T, B_R, [
        ("素心", 3, {"skill:yunv:damage": 0.06}, "兰溪双影剑伤害 +6%/级"),
        ("回春一转", 3, {"skill:yunv:heal": 0.01}, "命中回复气血 +1%/级（受吸血上限限制）"),
        ("双影叠舞", 2, {"t_shuangying": 1}, "回身一圈后追加第二圈，伤害 40%/70%"),
        ("兰溪长流", 1, {"t_lanxi": 1}, "终极：回身时清除身周弹幕，并获得 3 秒移速 +20%")]) +
    generic("sr_g", [
        ("轻灵", 3, {"speed_pct": 0.015}, "移速 +1.5%/级"),
        ("剑气外放", 4, {"t_jianqi": 1}, "近战挥砍额外向前飞出一道远程波（伤害 30%/级）"),
        ("控场易伤", 3, {"t_kongchang": 1}, "攻击被定身 / 减速的敌人，暴击率 +15%/级"),
        ("调息", 3, {"hp_regen": 0.3}, "气血回复 +0.3/秒每级"),
        ("灵犀一点", 4, {"crit_mult": 0.08}, "暴击伤害 +8%/级"),
        ("凌波", 5, {"speed_pct": 0.015}, "移速 +1.5%/级")], GEN_TIERS, GEN_ROWS, GEN_MODES))
sw_rou.append(N("sr_peak", "阴柔回春", 1, 8, 1.5, 9, {"burst_yin": 1},
                "巅峰：阴性内力（双阴）：真气爆发时额外回血，并获得 8 秒攻速 +30%", peak=True))

M5 = [None, ONE, FULL, FULL, FULL]
T5, R5 = [1, 2, 4, 5, 7], [1, 2, 4, 5, 7]
M3 = [None, ONE, FULL]
T3, R3 = [1, 3, 7], [1, 3, 7]
sw_ling = (
    chainN("sl_a", 0, T5, R5, M5, [
        ("初悟", 3, {"t_chuwu": 1}, "开局自带「总纲变」1/2/3 层"),
        ("悟性", 1, {"t_wuxing": 1}, "可同时领悟的「变」种类 +2（4 → 6 种）；代价：破兵微步 / 万法皆破 / 觉醒的层数门槛从 9 / 18 / 27 变成 11 / 22 / 33"),
        ("破兵微步·强", 3, {"t_pobing": 1}, "破兵微步触发时，2 秒内移速 +10%/20%/30%，并让命中的敌人易伤 +4%/7%/10%（3 秒）"),
        ("万法皆破·强", 2, {"t_wanfa": 1}, "斩落的每一发敌方弹幕，回复 0.5/1 点内力"),
        ("真·九变", 1, {"t_zhenbian": 1}, "终极：觉醒（总层数达到觉醒门槛）后，真气爆发变成冷却型——不再限制次数，每 30 秒一次")]) +
    chainN("sl_b", 1, T5, R5, M5, [
        ("复剑", 4, {"t_fujian": 1}, "每次出剑有 8%/16%/24%/32% 几率额外「复剑」：同样的剑气再发一次（伤害 60%）"),
        ("分锋合流", 2, {"t_fenfeng": 1}, "分锋变多出的剑，命中同一敌人时每柄再叠 +8%/16% 伤害（最多叠 5 层）"),
        ("贯甲破甲", 2, {"t_guanjia": 1}, "九变剑命中的敌人防御 −8%/15%（3 秒，可叠）"),
        ("掠空疾电", 2, {"t_lvekong": 1}, "剑气飞行越远伤害越高，最远处 +30%/60%"),
        ("万剑朝宗", 1, {"t_wanjian_cap": 1}, "终极：每第 9 次出剑，向周围一圈同时射出 9 道剑气（伤害 50%）")]) +
    chainN("sl_c", 2, T5, R5, M5, [
        ("折锋连环", 3, {"t_zhefeng": 1}, "折锋变的弹射次数 +1/2/3，弹射后伤害不再衰减"),
        ("滞步冰封", 2, {"t_zhibu": 1}, "滞步变定身几率 +10%/20%；被定身的敌人受到九变剑伤害 +15%/30%"),
        ("震浪叠浪", 2, {"t_zhenlang": 1}, "震浪变爆开后，0.4 秒再爆一次（伤害 40%/70%）"),
        ("落矢反射", 2, {"t_luoshi": 1}, "被斩落的敌方普通投射物，50%/100% 几率反射回去"),
        ("九变归一", 1, {"t_guiyi": 1}, "终极：每领悟新的「变」或总层数 +1 时，下一次出剑伤害 +50% 并重置冷却")]) +
    chainN("sl_d", 3, T3, R3, M3, [
        ("掠光", 3, {"skill:pixie:range": 0.10}, "残影掠光剑闪现距离 / 范围 +10%/级"),
        ("影随身动", 2, {"t_yingsui": 1, "damage_pct": 0.05}, "闪现后 2 秒内下一次攻击伤害 +20%/40%，并使全部招式伤害 +5%/级"),
        ("欲练神功·极", 1, {"t_yulian": 1}, "终极：闪现留下残影，1 秒后再刺一次（伤害 100%）")]) +
    chainN("sl_e", 4, T3, R3, M3, [
        ("剑冢", 3, {"skill:wanjian:targets": 1.0}, "千锋聚啸剑飞剑 +1/级"),
        ("剑阵不灭", 2, {"t_jianzhen": 1, "damage_pct": 0.05}, "分裂出的小剑持续 +30%/60%，并使全部招式伤害 +5%/级"),
        ("万剑归宗", 1, {"t_wanjian_gui": 1}, "终极：飞剑飞到尽头后折返，再射一次（伤害 50%）")]) +
    chainN("sl_f", 5, T3, R3, M3, [
        ("曲锋缠丝", 3, {"skill:jinshe:targets": 1.0}, "蜿蜒曲锋剑曲锋锥 +1/级"),
        ("毒雾弥漫", 2, {"t_duwu": 1, "crit_chance": 0.04}, "中毒者死亡时毒雾爆开（不强化也会，50% 伤害），范围 +30%/60%，并使暴击率 +4%/级"),
        ("万毒归心", 1, {"t_wandu": 1}, "终极：毒层 ≥5 的敌人立刻引爆，造成已积毒伤 ×2")]))
sw_ling.append(N("sl_peak", "剑魔", 1, 8, 2.5, 9, {"skill:dugu:damage": 0.12, "skill:dugu:crit": 0.06, "skill:dugu:cooldown": 0.08, "crit_mult": 0.06},
                 "巅峰：无迹九变剑伤害 +12%、暴击率 +6%、冷却 −8%，暴击伤害 +6%", peak=True))

BRANCH = {
    "gang": {"name": "刚", "sub": "近身重击 · 破防 · 击晕", "starter": "chain_fist", "nodes": gang},
    "rou": {"name": "柔", "sub": "控制 · 清场 · 化解反击", "starter": "point_finger", "nodes": rou},
    "ling": {"name": "灵", "sub": "追踪 · 贯穿 · 多向", "starter": "cloud_palm", "nodes": ling},
}
COLS = {"gang": ["连山贯日拳", "沉岳铁拳", "裂脉震拳", "通用"], "rou": ["凝霜点指", "乱花拂柳掌", "回澜卸力诀", "通用"],
        "ling": ["朔雪融阳掌", "撼岳惊涛掌", "四野归元功", "通用"]}

COL_SKILLS = {"gang": ["chain_fist", "vajra_fist", "quake_fist"], "rou": ["point_finger", "whirl_palm", "taiji"], "ling": ["cloud_palm", "yue_palm", "eight_waste"]}

# ======================= 刀客 =======================
bl_gang = (
    chain("bg_a", 0, A_T, A_R, [
        ("断门", 3, {"skill:wuhu_blade:damage": 0.08}, "五煞断岳刀伤害 +8%/级"),
        ("虎啸", 3, {"skill:wuhu_blade:range": 0.08}, "范围 +8%/级"),
        ("撕裂入骨", 2, {"t_sliegu": 1, "bleed_pow": 0.1}, "命中叠的撕裂层数 +1，撕裂伤害 +10%/20%"),
        ("猛虎下山·极", 1, {"t_menghu": 1}, "终极：流血的敌人死亡时爆出刀气，对周围 100 范围造成 80% 伤害")]) +
    chain("bg_b", 1, B_T, B_R, [
        ("斩蛟余威", 3, {"skill:tulong_art:range": 0.10}, "斩蛟沉海刀范围 +10%/级"),
        ("沉海", 3, {"skill:tulong_art:damage": 0.08}, "伤害 +8%/级"),
        ("浪涌", 2, {"t_langyong": 1}, "全场减速更强（−15%/30%）、更久（+0.5/1 秒）"),
        ("蛟龙出海", 1, {"t_jiaolong": 1}, "终极：落地 1 秒后再涌起一道巨浪（伤害 50%）")]) +
    chain("bg_c", 2, B_T, B_R, [
        ("裂地", 3, {"skill:xuanxu_blade:damage": 0.08}, "幽微藏锋刀伤害 +8%/级"),
        ("绵延", 3, {"skill:xuanxu_blade:range": 0.08}, "范围 +8%/级"),
        ("处决", 2, {"t_chujue": 1}, "对被震晕 / 定身的敌人额外伤害 +20%/40%"),
        ("开山·极", 1, {"t_kaishan": 1}, "终极：裂地刀痕由 3 道变 5 道")]) +
    generic("bg_g", [
        ("刚劲", 3, {"damage_pct": 0.02}, "招式伤害 +2%/级"),
        ("聚魂", 3, {"soul_gain": 0.15}, "刀魂增长 +15%/级"),
        ("魂火余烬", 3, {"t_hunhuo": 1}, "霸刀破岳后保留 10%/级 的刀魂"),
        ("破岳·余震", 3, {"t_poyue": 1}, "霸刀破岳 0.6 秒后再劈一次（30%/50%/70%）"),
        ("破军", 4, {"crit_mult": 0.1}, "暴击伤害 +10%/级"),
        ("破盾", 3, {"t_podun": 1}, "霸刀破岳击碎护盾 / 罡气时，晕眩敌人 1 秒/级"),
        ("魂爆", 2, {"t_hunbao": 1}, "霸刀破岳后 3 秒内刀魂增长 ×1.5 / ×2"),
        ("霸刀无双", 1, {"t_bawu": 1}, "终极：刀魂只需攒到 80 就触发霸刀破岳，破岳时范围 +30%")], SIG_TIERS, SIG_ROWS, SIG_MODES))
bl_gang.append(N("bg_peak", "狂刀喋血", 1, 8, 1.5, 9, {"burst_yang": 1, "ying_dmg": 0.1, "lowhp_dmg": 0.03},
                 "巅峰：阳性内力，盈境伤害 +10%；气血每降低 10%，全部伤害再 +3%", peak=True))
bl_rou = (
    chain("br_a", 0, A_T, A_R, [
        ("暴风刀势", 3, {"skill:kuangfeng_blade:cooldown": 0.08}, "暴风卷沙刀冷却 −8%/级"),
        ("卷沙", 3, {"skill:kuangfeng_blade:damage": 0.08}, "伤害 +8%/级"),
        ("撕裂引爆", 2, {"t_liebao": 1}, "每第 4 次出刀引爆撕裂的伤害 +30%/60%"),
        ("风卷残云·极", 1, {"t_fengjuan": 1}, "终极：引爆时，周围一圈敌人各叠 2 层撕裂")]) +
    chain("br_b", 1, B_T, B_R, [
        ("饮锋", 3, {"skill:xuedao:damage": 0.08}, "朱砂饮锋刀伤害 +8%/级"),
        ("血刃", 3, {"skill:xuedao:heal": 0.12}, "吸回气血 +12%/级（受吸血上限限制）"),
        ("血债", 2, {"t_xuezhai": 1}, "朱砂饮锋刀耗血减少 25%/50%"),
        ("血魔不死·极", 1, {"t_xuemo": 1}, "终极：气血低于 50% 时，每击杀一个敌人回复 2% 气血")]) +
    chain("br_c", 2, B_T, B_R, [
        ("两仪化气", 3, {"skill:fanliangyi:range": 0.12}, "错位双仪刀刀轮范围 +12%/级"),
        ("阴阳轮转", 3, {"skill:fanliangyi:duration": 0.10}, "刀轮持续 +10%/级"),
        ("反刃", 2, {"t_fanren": 1}, "刀轮期间受到的伤害，30%/60% 反弹给周围敌人"),
        ("混沌初开", 1, {"t_hundun": 1}, "终极：刀轮存续期间，每 0.5 秒向外放出一道刀气（伤害 40%）")]) +
    generic("br_g", [
        ("调息", 3, {"hp_regen": 0.4}, "气血回复 +0.4/秒每级"),
        ("血契", 3, {"t_xueqi": 1}, "耗血刀法耗血 −10%/级"),
        ("以血养刀", 3, {"t_yangdao": 1}, "每耗 1% 气血，2 秒内伤害 +2%/级"),
        ("撕裂易伤", 3, {"t_liexi": 1}, "撕裂 ≥5 层的敌人受到的伤害 +10%/级"),
        ("绵里藏针", 4, {"armor": 0.4}, "防御 +0.4/级"),
        ("饮血", 3, {"t_yinxue": 1}, "击杀回复 2%/级 气血"),
        ("血雾", 2, {"t_xuewu": 1}, "气血低于 50% 时，刀招额外叠 1 层撕裂"),
        ("血魂归一", 1, {"t_xuehun": 1}, "终极：自己耗的血转化为刀魂的比例 ×2")], SIG_TIERS, SIG_ROWS, SIG_MODES))
bl_rou.append(N("br_peak", "阴柔回春", 1, 8, 1.5, 9, {"burst_yin": 1},
                "巅峰：阴性内力：真气爆发时额外回血，并获得 8 秒攻速 +30%", peak=True))
bl_ling = (
    chain("bl_a", 0, A_T, A_R, [
        ("寒鸦", 3, {"skill:hujia_blade:damage": 0.08}, "寒鸦落雪刀伤害 +8%/级"),
        ("穿云", 3, {"skill:hujia_blade:targets": 1.0}, "刀气贯穿 +1/级"),
        ("落单必杀", 2, {"t_luodan": 1}, "近处 / 落单目标的额外伤害 +20%/40%"),
        ("八方藏刀·极", 1, {"t_bafang": 1}, "终极：刀气飞到尽头折返一次（伤害 60%）")]) +
    chain("bl_b", 1, B_T, B_R, [
        ("烈焰", 3, {"skill:ranmu_blade:damage": 0.08}, "烈焰焚林刀伤害 +8%/级"),
        ("火海", 3, {"skill:ranmu_blade:range": 0.10}, "范围 +10%/级"),
        ("灼烧蔓延", 2, {"t_zhuoshao": 1}, "被灼烧的敌人死亡时，在它脚下再生出一小片火海"),
        ("燎原", 1, {"t_liaoyuan": 1}, "终极：火海持续时间 ×1.5，范围内敌人受到的灼烧伤害 +50%")]) +
    chain("bl_c", 2, B_T, B_R, [
        ("双鲤连环", 3, {"skill:yuanyang_blade:targets": 1.0}, "双鲤戏浪刀飞刀 +1 对/级"),
        ("戏浪", 3, {"skill:yuanyang_blade:damage": 0.08}, "伤害 +8%/级"),
        ("逆流", 2, {"t_niliu": 1}, "飞刀折返时伤害 +25%/50%"),
        ("仁义无双·极", 1, {"t_renyi": 1}, "终极：被长刀减速又被短刀撕裂的敌人，易伤 +25% 并下一击必暴击")]) +
    generic("bl_g", [
        ("蓄势", 4, {"t_xushib": 1}, "真·霸刀破岳持续 +1 秒/级"),
        ("绝境", 3, {"t_juejing": 1}, "真·霸刀破岳的触发线从气血 20% 提高到 25% / 30% / 35%"),
        ("回复加深", 3, {"t_huifu": 1}, "真·霸刀期间回复倍率 ×2 → ×2.3 / 2.6 / 3"),
        ("浴血", 3, {"t_yuxue": 1}, "真·霸刀期间每击杀回复 1%/级 气血"),
        ("余威", 3, {"t_yuweib": 1}, "真·霸刀结束后 5 秒内，全部伤害 +8%/级"),
        ("不灭", 3, {"t_bumie": 1}, "真·霸刀期间受到的伤害 −10%/级"),
        ("重燃", 2, {"t_chongran": 1}, "真·霸刀冷却 30 秒 → 24 / 18 秒"),
        ("刀魂不灭", 1, {"t_hunbumie": 1}, "终极：真·霸刀期间每一刀都附带 50% 的霸刀破岳效果")], SIG_TIERS, SIG_ROWS, SIG_MODES))
bl_ling.append(N("bl_peak", "刀皇霸体", 1, 8, 1.5, 9, {"burst_harmony": 1, "cd_reduce": 0.05, "max_hp": 10},
                 "巅峰：调和内力：真气爆发次数 ×2；招式冷却 −5%，气血上限 +10", peak=True))


# ======================= 杨家将 =======================
sp_gang = (
    chain("pg_a", 0, A_T, A_R, [
        ("力劈华山", 3, {"skill:shaolin_staff:damage": 0.08}, "少林棍法伤害 +8%/级"),
        ("横扫", 3, {"skill:shaolin_staff:range": 0.08}, "范围 +8%/级"),
        ("棍势满溢", 2, {"t_gunshi": 1}, "打出「横扫千军」后立刻再攒 15/30 点棍势"),
        ("大开大合·极", 1, {"t_dakai": 1}, "终极：少林棍法每第 2 下（原本第 3 下）变成 360° 横扫")]) +
    chain("pg_b", 1, B_T, B_R, [
        ("怒涛", 3, {"skill:fengmo_staff:damage": 0.08}, "怒涛狂澜杖伤害 +8%/级"),
        ("狂澜", 3, {"skill:fengmo_staff:duration": 0.10}, "旋转持续 +10%/级"),
        ("魔音", 2, {"t_moyin": 1}, "旋转结束的冲击波伤害 +40%/80%（不强化也会震出）"),
        ("风魔·极", 1, {"t_fengmo": 1}, "终极：旋转时每 0.3 秒把近身敌人向中心吸拢")]) +
    chain("pg_c", 2, B_T, B_R, [
        ("降魔怒目", 3, {"skill:xiangmo_staff:damage": 0.08}, "定海铁杖伤害 +8%/级"),
        ("镇海", 3, {"skill:xiangmo_staff:range": 0.08}, "范围 +8%/级"),
        ("震慑", 2, {"skill:xiangmo_staff:duration": 0.3}, "击晕时间 +30%/60%"),
        ("金刚震地·极", 1, {"t_jingangz": 1}, "终极：冲击波每命中一个敌人，下一次出手冷却 −0.3 秒（最多 −2 秒）")]) +
    generic("pg_g", [
        ("刚劲", 3, {"damage_pct": 0.02}, "招式伤害 +2%/级"),
        ("聚势", 3, {"gs_gain": 0.15}, "近身命中 / 格挡攒棍势 +15%/级"),
        ("横扫·余震", 3, {"t_hsyz": 1}, "横扫千军 0.6 秒后再扫一次（30%/50%/70%）"),
        ("破阵棍", 3, {"t_pzg": 1}, "横扫千军命中的敌人防御 −10%/级（3 秒）"),
        ("破军", 4, {"crit_mult": 0.1}, "暴击伤害 +10%/级"),
        ("蓄势待扫", 3, {"t_xsds": 1}, "棍势满时暴击率 +10%/级"),
        ("连扫", 2, {"t_liansao": 1}, "横扫千军后有 12%/24% 几率保留一半棍势"),
        ("横扫天下", 1, {"t_hengsao_cap": 1}, "终极：横扫千军范围 +10%，击退 ×1.3 并打断晕眩 0.35 秒")], SIG_TIERS, SIG_ROWS, SIG_MODES))
sp_gang.append(N("pg_peak", "金刚不坏", 1, 8, 1.5, 9, {"block_chance": 0.05, "crit_mult": 0.1}, "巅峰：格挡几率 +5%，暴击伤害 +10%", peak=True))
sp_rou = (
    chain("pr_a", 0, A_T, A_R, [
        ("蟠龙盘旋", 3, {"skill:panlong_staff:duration": 0.12}, "蟠龙棍法守势时间 +12%/级"),
        ("龙影", 3, {"skill:panlong_staff:damage": 0.08}, "伤害 +8%/级"),
        ("龙影追击", 2, {"t_longying": 1}, "每次成功格挡，龙影额外反击一次（60%/100%）"),
        ("龙腾九天·极", 1, {"t_longteng": 1}, "终极：守势期间格挡几率再 +20%（仍受上限），守势结束的砸落范围 ×1.5")]) +
    chain("pr_b", 1, B_T, B_R, [
        ("绊腿", 3, {"skill:dagou_staff:damage": 0.08}, "翠竹巧拨棒伤害 +8%/级"),
        ("天下无狗", 3, {"skill:dagou_staff:duration": 0.10}, "绊倒时间 +10%/级"),
        ("露出破绽", 2, {"t_pozhan": 1}, "被绊倒（定身）的敌人受到的伤害 +15%/30%"),
        ("打狗阵", 1, {"t_dagouzhen": 1}, "终极：点地时在身周一圈再绊一次")]) +
    chain("pr_c", 2, B_T, B_R, [
        ("无名之势", 3, {"skill:wuming_spear:crit": 0.05}, "无名枪法暴击率 +5%/级"),
        ("破防", 3, {"skill:wuming_spear:pierce_def": 0.10}, "无视防御额外 +10%/级"),
        ("无名之名", 2, {"t_wmzm": 1}, "击杀敌人后，下一次无名枪法伤害 +25%/50%"),
        ("返璞归真", 1, {"t_fanpu": 1}, "终极：对 Boss 伤害 ×1.5，防御削弱从 5 秒延长到 8 秒")]) +
    generic("pr_g", [
        ("调息", 3, {"hp_regen": 0.3}, "气血回复 +0.3/秒每级"),
        ("卸力", 3, {"t_xieli_b": 1}, "格挡成功的震退范围 +30%/级"),
        ("反击", 3, {"t_fanji": 1}, "格挡成功自动反击周围一枪（50%/80%/110%）"),
        ("铁壁连环", 3, {"t_tiebi": 1}, "格挡成功后 1 秒内格挡几率 +10%/级"),
        ("铁壁", 4, {"block_chance": 0.02}, "格挡几率 +2%/级"),
        ("无懈可击", 3, {"t_wuxie": 1}, "格挡几率上限 70% → 75% / 80% / 85%"),
        ("以守为攻", 2, {"t_yishou": 1}, "每格挡 4/3 次，下一击伤害 ×1.5/×2"),
        ("万法归宗", 1, {"t_wanfa_gui": 1}, "终极：任意招式的每次命中都同时攒枪势和棍势、计连击；「游龙突」「横扫千军」可由任意枪棍打出")], SIG_TIERS, SIG_ROWS, SIG_MODES))
sp_rou.append(N("pr_peak", "阴柔回春", 1, 8, 1.5, 9, {"burst_yin": 1}, "巅峰：阴性内力：真气爆发时额外回血，并获得 8 秒攻速 +30%", peak=True))
sp_ling = (
    chain("pl_a", 0, A_T, A_R, [
        ("回马无双", 3, {"skill:yangjia_spear:range": 0.08}, "杨家枪法射程 +8%/级"),
        ("杨家", 3, {"skill:yangjia_spear:damage": 0.08}, "伤害 +8%/级"),
        ("枪尖淬火", 2, {"tip_dmg": 0.1}, "枪尖伤害 +10%/20%"),
        ("回马连环·极", 1, {"t_huima": 1}, "终极：打出「游龙突」后 3 秒内，杨家枪法冷却 −50%")]) +
    chain("pl_b", 1, B_T, B_R, [
        ("梅花点点", 3, {"skill:meihua_spear:targets": 1.0}, "梅花枪法枪数 +1/级"),
        ("落梅", 3, {"skill:meihua_spear:damage": 0.08}, "伤害 +8%/级"),
        ("五瓣连环", 2, {"t_wuban": 1}, "梅花枪每次命中累计的连击 +1/+2"),
        ("梅花雨", 1, {"t_meihuayu": 1}, "终极：每第 5 次出枪变成环绕一圈的梅花雨（枪数 ×2）")]) +
    chain("pl_c", 2, B_T, B_R, [
        ("白马蹄疾", 3, {"skill:baima_spear:cooldown": 0.10}, "白马银枪冷却 −10%/级"),
        ("银龙", 3, {"skill:baima_spear:damage": 0.08}, "伤害 +8%/级"),
        ("踏雪", 2, {"skill:baima_spear:range": 0.30}, "冲刺距离 / 范围 +30%/60%"),
        ("一骑绝尘", 1, {"t_yiqi": 1}, "终极：冲刺路径留下 2 秒枪痕，持续伤害路过的敌人")]) +
    generic("pl_g", [
        ("轻灵", 3, {"speed_pct": 0.015}, "移速 +1.5%/级"),
        ("点穴", 3, {"t_dianxue": 1}, "枪尖命中后追击一枪（30%/50%/70%）"),
        ("游龙·余势", 3, {"t_youlong": 1}, "游龙突的枪龙长度 +15%/级"),
        ("连击枪影", 3, {"t_yingying": 1}, "枪影所需连击从 10 降到 8 / 6 / 5"),
        ("枪走游龙", 4, {"qs_gain": 0.15}, "枪势攒速 +15%/级"),
        ("枪影·扩", 3, {"t_yingk": 1}, "枪影追击目标 3 → 4 / 5 / 6"),
        ("乘胜", 2, {"t_chengsheng": 1}, "连击 ≥10 时暴击率 +8%/16%"),
        ("枪出如龙", 1, {"t_qiangchu": 1}, "终极：每第 5 次枪路出手，游龙突无需攒势")], SIG_TIERS, SIG_ROWS, SIG_MODES))
sp_ling.append(N("pl_peak", "神枪合一", 1, 8, 1.5, 9, {"burst_harmony": 1, "qs_gain": 0.2, "gs_gain": 0.2}, "巅峰：调和内力：真气爆发次数 ×2；枪势 / 棍势攒速 +20%", peak=True))

def assign_gates(nodes):
    """每个节点的层门槛 = 该层的总投入门槛；但普通节点最多要求「本链前面节点的点数之和」，
    所以任何一条链都可以先单点、一路点到终极前一格；终极（需 25）和巅峰（需 36）必须靠别的链凑够。"""
    prior = {}
    for n in nodes:
        g = GATES[n["tier"] - 1]
        if not n["cap"] and not n["peak"]:
            prefix = n["id"].rsplit("_", 1)[0]
            g = min(g, prior.get(prefix, 0))
        n["gate"] = g
        prior[n["id"].rsplit("_", 1)[0]] = prior.get(n["id"].rsplit("_", 1)[0], 0) + n["max"]


def build(ji, branches):
    for _b, (_n, _s, _st, _c, _cs, nodes) in branches.items():
        assign_gates(nodes)
        for n in nodes:                                    # 该节点强化的招式（局内抽卡时提示用）；通用链 / 巅峰没有
            ci = n["col"]
            if not n["peak"] and float(ci) == int(ci) and int(ci) < len(_cs) and _cs[int(ci)] != "":
                n["skill"] = _cs[int(ci)]
    out = {"gates": GATES, "ji": ji, "branches": {}}
    for b, (name, sub_, starter, cols, col_skills, nodes) in branches.items():
        out["branches"][b] = {"name": name, "sub": sub_, "starter": starter, "cols": cols, "col_skills": col_skills, "nodes": nodes}
        tot = sum(n["max"] for n in nodes)
        assert tot == 50, (b, tot)
    return out


fist = build({"id": "fist_ji", "name": "极意·天人合一", "max": 1, "need": 99, "stat": {"ji_fist": 1.0},
              "desc": "武者之极意：拳掌无敌持续 +5 秒；蓄劲速度翻倍；多 1 次真气爆发；拳掌无敌结束时回复 40% 内力"},
             {b: (d["name"], d["sub"], d["starter"], COLS[b], COL_SKILLS[b], d["nodes"]) for b, d in BRANCH.items()})
sword = build({"id": "sword_ji", "name": "极意·千锋聚啸剑", "max": 1, "need": 99, "stat": {"ji_sword": 1.0},
               "desc": "剑侠之极意：所有招式冷却 −20%；每次冲刺 / 闪现后 3 秒内冷却再 −40%、移速 +25%；无迹九变剑的 2 / 4 / 9 连击几率 ×1.25"},
              {"gang": ("刚", "近身刺击 · 重击 · 破甲", "qingsong", ["劲柏凌霜剑", "沉渊重剑", "断云裂帛剑", "通用"], ["qingsong", "zhongjian", "yitian"], sw_gang),
               "rou": ("柔", "快剑 · 回旋 · 回春", "kuang_feng", ["猎风疾影剑", "圆转绵剑", "兰溪双影剑", "通用"], ["kuang_feng", "taiji_sword", "yunv"], sw_rou),
               "ling": ("灵", "九变 · 远程 · 身法", "dugu", ["九变·根基", "九变·攻势", "九变·控势", "残影掠光剑", "千锋聚啸剑", "蜿蜒曲锋剑"],
                        ["dugu", "dugu", "dugu", "pixie", "wanjian", "jinshe"], sw_ling)})
blade = build({"id": "blade_ji", "name": "极意·霸刀", "max": 1, "need": 99, "stat": {"ji_blade": 1.0},
               "desc": "刀客之极意：真·霸刀破岳持续 +5 秒、冷却减半；刀法耗血减半；刀魂增长 +50%；霸刀 / 破岳回复已损气血的比例翻倍"},
              {"gang": ("刚", "刀魂 · 霸刀破岳 · 重劈", "wuhu_blade", ["五煞断岳刀", "斩蛟沉海刀", "幽微藏锋刀", "刀魂"], ["wuhu_blade", "tulong_art", "xuanxu_blade"], bl_gang),
               "rou": ("柔", "撕裂 · 耗血 · 回春", "kuangfeng_blade", ["暴风卷沙刀", "朱砂饮锋刀", "错位双仪刀", "血债"], ["kuangfeng_blade", "xuedao", "fanliangyi"], bl_rou),
               "ling": ("灵", "飞刀 · 火海 · 绝境", "hujia_blade", ["寒鸦落雪刀", "烈焰焚林刀", "双鲤戏浪刀", "绝境"], ["hujia_blade", "ranmu_blade", "yuanyang_blade"], bl_ling)})
spear = build({"id": "spear_ji", "name": "极意·万军辟易", "max": 1, "need": 99, "stat": {"ji_spear": 1.0},
               "desc": "杨家将之极意：枪路——游龙突后只清一半枪势、枪尖区间扩大；棍路——横扫千军后立刻再攒 40 点棍势、格挡几率 +10%（格挡仍受上限）；格挡成功回复 3% 气血"},
              {"gang": ("刚", "棍势 · 横扫千军 · 重击", "shaolin_staff", ["少林棍法", "怒涛狂澜杖", "定海铁杖", "棍势"], ["shaolin_staff", "fengmo_staff", "xiangmo_staff"], sp_gang),
               "rou": ("柔", "格挡 · 守势 · 万法归宗", "", ["蟠龙棍法", "翠竹巧拨棒", "无名枪法", "守势"], ["panlong_staff", "dagou_staff", "wuming_spear"], sp_rou),
               "ling": ("灵", "枪势 · 游龙突 · 连击枪影", "yangjia_spear", ["杨家枪法", "梅花枪法", "白马银枪", "枪势"], ["yangjia_spear", "meihua_spear", "baima_spear"], sp_ling)})
sword["order"] = ["gang", "ling", "rou"]          # 剑客：灵系（九变）放在中间，刚柔在左右
(ROOT / "data" / "talent_trees.json").write_text(json.dumps({"fist": fist, "sword": sword, "blade": blade, "spear": spear}, ensure_ascii=False, indent=1), encoding="utf-8")
print("ok, 每系 50 点")
