class_name Story
extends RefCounted
## 剧情与局内互动台词（纯文案与轻剧情，不影响任何数值与战斗节奏）。
## 包含：
##   1. 四流派专属「进村开场」（老村长托付救铁匠）
##   2. 局内入场独白 / 小 Boss 叫阵 / 大 Boss 现身一唱一和 / 二阶段怒喝 / 绝境独白 / 合璧顿悟
##   3. 通关各关回村后的小村庆功与下关线索 + 江湖名号
##   4. 茶馆老包「列传」：四位主角的三章身世小传

const SCHOOL_TITLES := {
	"fist": "拳震山河",
	"sword": "白衣剑仙",
	"blade": "破岳刀皇",
	"spear": "忠烈枪魂",
}


static func honorific(school: String, cleared_th: bool) -> String:
	return str(SCHOOL_TITLES.get(school, "大侠")) if cleared_th else "少侠"


## 1. 新角色首次进村：老村长托付救铁匠（按流派定制性格与对话）
static func chief_intro(school: String) -> Dictionary:
	match school:
		"sword":
			return {
				"text": "这位白衣少侠请留步！见你腰挂酒葫芦、气度不凡，定是江湖剑客。\n\n村里的王铁匠前日去山脚收铁矿，被黑风寨恶贼抓上了山，如今连酒馆修壶的炉火都熄了。还请少侠走一遭黑风寨——只要熬到大当家现身之前，便能趁乱把铁匠救回来！",
				"opt1": "酒喝得不安生，我去去就回！（前往黑风寨）",
				"opt2": "先在村里讨碗酒再说",
			}
		"blade":
			return {
				"text": "戴斗笠的少侠请留步！村里的王铁匠前日去山脚收铁矿，被黑风寨那帮恶贼抓上了山。\n\n听说黑风铁锅王自称刀枪不入，村里无人敢上山。还请少侠前去黑风寨走一遭——只要熬到大当家现身之前，便能把铁匠救回村来！",
				"opt1": "刀枪不入？正好拿他试刀！（前往黑风寨）",
				"opt2": "先在村里看看",
			}
		"spear":
			return {
				"text": "这位少侠……你左肩的银甲与手中红缨枪，莫非是当年杨家军的旧物？！\n\n老朽失态了。村里的王铁匠前日被黑风寨恶贼掳上了山，乡亲们束手无策。恳请少侠护佑百姓，前去黑风寨——只要熬到大当家现身之前，便能把铁匠救回村来！",
				"opt1": "贼寇在前，断不退步！（前往黑风寨）",
				"opt2": "容我先整顿行装",
			}
	return {
		"text": "少侠，你可算来了！村里都知道你是附近苦修拳掌的侠义之士。\n\n王铁匠前日去山脚收铁矿，竟被黑风寨那帮恶贼抓上了山！如今打铁铺空荡荡的，兵甲无人锻打。还请少侠前去黑风寨走一遭——只要熬到大当家现身之前，便能趁乱把铁匠救回村来！",
		"opt1": "义不容辞，这就前往黑风寨！",
		"opt2": "先在村里四处转转",
	}


## 2. 局内入场独白（开局 2 秒飘在主角头顶，不暂停）
static func map_entry_line(school: String, map_id: String) -> String:
	match map_id:
		"black_wind":
			match school:
				"sword": return "山风带煞，倒适合醒酒。"
				"blade": return "黑风寨……今日便拿你们开刃。"
				"spear": return "山贼掳民，与边关匪患何异！"
			return "黑风寨，铁匠我今日定要带走！"
		"guangming":
			match school:
				"sword": return "昆仑绝顶群雄聚，正好一试剑心。"
				"blade": return "漫山火气，正合我刀魂之意！"
				"spear": return "赤焰高台，孤枪亦敢独闯！"
			return "赤焰巅上是非多，且以双拳问是非！"
		"taohua":
			match school:
				"sword": return "海风伴花香，这八卦阵倒是有趣。"
				"blade": return "什么奇门八门，一刀劈开便是！"
				"spear": return "沙场布阵我见多了，且看此阵虚实。"
			return "步步机关，正好锤炼气海心境。"
	return ""


## 3. 小 Boss 现身时的简短叫阵（不暂停）
static func mini_boss_banter(school: String, boss_id: String) -> String:
	match boss_id:
		"mini_boss_1":
			return "哪来的毛头小子，敢闯黑风寨！" if school != "spear" else "这杆红缨枪……莫非是官军？！"
		"mini_boss_2":
			return "让我算算你的命值几两银子！"
		"mini_boss_3":
			return "好久没见这么耐打的肉了！" if school != "blade" else "比比谁的刀更重！"
		"s2_mini_1":
			return "擅闯赤焰宗总坛者，留命！"
		"s2_mini_2":
			return "五行烈焰，岂容外人放肆！"
		"s2_mini_3":
			return "敢上昆仑巅，先过我这一关！"
		"th_mini_1":
			return "误入海棠阵，且试我奇门机关！"
		"th_mini_2":
			return "阵眼已动，少侠看清脚下了吗？"
		"th_mini_3":
			return "想见仙子，先破我这一关！"
	return ""


## 4. 三大最终 Boss 现身一唱一和（返回 [Boss 台词, 主角回呛]）
static func final_boss_exchange(school: String, map_id: String, dugu_awakened: bool = false) -> Array:
	match map_id:
		"black_wind":
			match school:
				"sword": return ["白衣书生，提着酒葫芦也敢闯我黑风寨？", "酒还未凉，足够斩你！"]
				"blade": return ["哼，你的破刀劈得开老子的玄铁大锅吗？", "一刀破岳，连人带锅一起劈！"]
				"spear": return ["杨家枪？！你不是早该埋在边关了吗！", "故军未绝，今日先拿你祭旗！"]
			return ["敢在黑风寨撒野，先尝尝我的铁锅！", "空手双拳，照样掀翻你这贼窝！"]
		"guangming":
			match school:
				"sword":
					if dugu_awakened:
						return ["好凌厉的九变剑意……你究竟师出何门？！", "无迹可寻，请掌门赐教！"]
					return ["区区白衣剑客，也配在赤焰巅与我论剑？", "剑在手中，何须多言！"]
				"blade": return ["好凶猛的刀魂！正好用你祭我赤焰神功！", "谁祭谁，刀下见分晓！"]
				"spear": return ["边关余孽也敢孤身闯我昆仑总坛？", "一枪一棍，足破你满山烈焰！"]
			return ["好纯正的内家拳劲，可惜今日要折在此处！", "气海盈满，正要领教掌门高招！"]
		"taohua":
			match school:
				"sword": return ["白衣持剑破八门，倒真有几分剑仙气象。", "阵法精妙，请仙子再赐一招！"]
				"blade": return ["以蛮力破我奇门八阵，刀客果然狂傲！", "刀魂所指，万阵皆虚！"]
				"spear": return ["以沙场军阵破我海棠迷阵，好一位杨家将！", "兵法奇门本同源，请仙子指教！"]
			return ["拳意通明，竟能踏破我海棠八卦阵！", "承让了，请仙子亮出真本事！"]
	return []


## 5. 最终 Boss 二阶段怒喝（不暂停）
static func phase2_line(school: String, map_id: String) -> String:
	match map_id:
		"black_wind":
			return "气煞我也！真当我黑风铁锅王是泥捏的？！"
		"guangming":
			return "竟逼出我护体真气……赤焰焚天！" if school != "blade" else "好重的刀势！看你破不破得开我护体罡气！"
		"taohua":
			return "有点意思……八门齐转，真阵方始！"
	return ""


## 6. 局内高光 / 绝境独白（每局各最多 1 次，绝不刷屏）
static func low_hp_line(school: String) -> String:
	match school:
		"sword": return "酒未凉，剑未钝……还能再战！"
		"blade": return "这点伤，正好养刀！"
		"spear": return "杨家儿郎，宁折不弯！"
	return "气沉丹田，绝处逢生！"


static func harmony_line(school: String, harmony_name: String) -> String:
	match school:
		"sword": return "「%s」成，剑意更添三分！" % harmony_name
		"blade": return "「%s」既成，刀魂沸腾！" % harmony_name
		"spear": return "「%s」贯通，枪棍如臂使指！" % harmony_name
	return "「%s」融会贯通，气海澄明！" % harmony_name


## 7. 王铁匠获救后首次在村里对话的专属感谢
static func smith_thanks(school: String) -> String:
	match school:
		"spear": return "恩公回来了！当年我也曾替杨家军打过枪头，今日能再为恩公锻兵，老王死而无憾！"
		"blade": return "恩公！那日见你一刀劈开山贼，真是痛快！以后打铁锻刀，老王定拿出压箱底的手艺！"
		"sword": return "恩公！酒馆的铜酒壶我也顺手修好了。今后但凡得了好兵甲，尽管拿来找老王淬火！"
	return "恩公总算平安回村了！那日被绑在黑风寨柴房里可吓坏老王了，今后锻打装备尽管交给我！"


## 8. 首通各关回村后的庆功剧情（自然引出下一张地图，零数值影响）
static func town_milestone(flag: String, school: String) -> Dictionary:
	var title := str(SCHOOL_TITLES.get(school, "大侠"))
	match flag:
		"bw_clear":
			return {
				"speaker": "老村长", "title": "小村村长", "tex": "res://assets/town/npc/chief.png",
				"text": "少侠凯旋！黑风铁锅王伏诛的消息已经传遍十里八乡，王铁匠的打铁铺也重新红火起来了！\n\n对了，方才过路的商队说起，昆仑山「赤焰巅」如今正被五大派围攻，赤焰宗灭灶掌门更是放言邀天下群雄上山。少侠若想再攀武道高峰，不妨去驿站看看。",
				"opt": "昆仑赤焰巅？我去会会他们！",
			}
		"gm_clear":
			return {
				"speaker": "茶馆老包", "title": "江湖百晓生", "tex": "res://assets/town/npc/sage.png",
				"text": "好家伙！少侠在赤焰巅连挫赤焰三堂主、力压灭灶掌门的事，茶馆里都传疯了！\n\n老包刚收到东海飞鸽传书——终年大雾的「海棠屿」近日雾散阵开，岛主千机仙子摆下八卦迷阵，专候能破阵的当世奇才。少侠可敢去东海走一遭？",
				"opt": "东海八卦迷阵，正合我意！",
			}
		"th_clear":
			return {
				"speaker": "掌柜", "title": "客栈掌柜", "tex": "res://assets/town/npc/innkeeper.png",
				"text": "满堂喝彩！连东海海棠屿的千机仙子都对你心服口服，如今整个江湖都尊称你一声「%s」！\n\n小店备下了最好的陈年女儿红，全村老少都记着你的恩情。无论何时倦了，小村永远为你留着灯火与热酒。" % title,
				"opt": "多谢诸位，江湖路长，来日方长！",
			}
	return {}


## 9. 茶馆老包「列传」：四位主角的三章身世小传（随通关进度解锁）
static func bio_entries(school: String, cleared_bw: bool, cleared_gm: bool, cleared_th: bool) -> Array:
	var chapters: Array = []
	match school:
		"sword":
			chapters = [
				["一 · 白衣酒葫芦", true,
					"无人知晓这名白衣青年师承何处。他腰间总挂着一只磨得发亮的棕漆酒葫芦，剑鞘素净无纹，行止随性，唯独出剑时如清风掠影、无迹可寻。\n\n他常说：「招式有尽，剑意无穷。若执着于一招一式，便落了下乘。」"],
				["二 · 黑风解围", cleared_bw,
					"路过无名小村那日，他本只想讨碗热酒，听闻村里王铁匠被黑风寨恶贼掳走，便提剑上山。一战破寨救出铁匠，剑气惊散满山贼众，自此白衣剑客之名传遍十里八乡。"],
				["三 · 昆仑论剑", cleared_gm,
					"黑风寨一役后，他在昆仑赤焰巅的漫天火光中仍从容饮酒，以九变剑意破去赤焰宗重重剑网，令五大派群雄尽皆侧目。\n\n「酒要半醉，剑要忘形，如此方见真意。」"],
				["四 · 白衣剑仙", cleared_th,
					"东海海棠屿雾散之日，他踏着八卦生门直入阵心，与千机仙子论招百合而不乱丝毫。自此江湖盛传「白衣剑仙」之名，而他却仍爱回到无名小村，靠在老柳树下听风小酌。"],
			]
		"blade":
			chapters = [
				["一 · 斗笠狂刀", true,
					"黑衣、竹笠、赤金披风，这名刀客从不报家门。他背负一口寒光凛冽的弯刀，越是绝境越是战意沸腾——旁人畏惧伤痛，他却以伤养魂，待刀魂盈满，一刀便可破岳裂石。\n\n「刀不出鞘则已，出鞘必见分晓。」"],
				["二 · 试刃黑风", cleared_bw,
					"听闻黑风铁锅王自称刀枪不入，他提刀上山，先斩柴房铁链救出王铁匠，再以霸刀破岳一刀劈碎玄铁大锅。自此村里人虽敬畏他的冷面，却都记住了他的恩情。"],
				["三 · 烈焰破盾", cleared_gm,
					"劈碎黑风铁锅王的玄铁巨锅后，他孤身登上昆仑赤焰巅。面对赤焰宗层层护体罡气，他以破岳刀势连斩护盾、血爆十方，连灭灶掌门也不得不叹一声霸道。\n\n「什么护体神功，劈不开只是刀魂未满。」"],
				["四 · 破岳刀皇", cleared_th,
					"海棠屿的奇门八阵困住了无数好手，他却只凭一股一往无前的狂刀气势硬生生劈开一条血路。江湖从此敬称「破岳刀皇」，唯独小村的王铁匠知道，这位冷面刀客每次回村都会悄悄给村口添一捆干柴。"],
			]
		"spear":
			chapters = [
				["一 · 孤枪旧甲", true,
					"左肩斑驳的银甲、系着褪色红缨的长枪、背上那根陪伴多年的白蜡杆——他是前杨家军最后的生还者。昔日边关血战，袍泽尽没，唯有他带着杨家枪棍绝学活了下来。\n\n「枪守家国，棍护苍生。只要我还站着，贼寇便休想过此一步。」"],
				["二 · 护民救匠", cleared_bw,
					"听闻黑风寨山贼掳走小村铁匠，他二话不说提枪上山。红缨枪如游龙破阵，先将王铁匠平安送下山，再斩黑风铁锅王，守住了一方乡邻的安宁。"],
				["三 · 昆仑问义", cleared_gm,
					"踏平黑风寨后，他听闻昆仑赤焰巅动乱波及山麓百姓，便再度提枪上山。游龙突刺破开烈焰，蟠龙棍势稳如泰山，让江湖中人重新记起了杨家将的威名。\n\n「我非为虚名而战，只为不负故人所托。」"],
				["四 · 忠烈枪魂", cleared_th,
					"在海棠屿八卦迷阵中，他以沙场行军布阵之法反破奇门遁甲，赢得千机仙子由衷敬重。江湖尊其为「忠烈枪魂」，每当夕阳西下，他总会擦净枪尖红缨，遥望北方边关。"],
			]
		_:
			chapters = [
				["一 · 问拳草莽", true,
					"出身无名山野的年轻武者，没有名门秘传，只凭一双铁拳与日复一日打磨出的深厚气海行走江湖。他信奉「刚柔并济、盈虚相生」，越是危难关头越沉得住气。\n\n「拳脚无兵刃之利，却有血肉之诚。」"],
				["二 · 铁拳救匠", cleared_bw,
					"初入小村便闻王铁匠被黑风寨掳走，他赤手空拳闯上山寨，连破三名头目救下铁匠，更以寸劲震爆击碎黑风铁锅王的铁锅，赢得全村交口称赞。"],
				["三 · 寸劲震岳", cleared_gm,
					"从黑风寨救回王铁匠后，他一路打上昆仑赤焰巅。寸劲震爆撕裂赤焰罡气，连山贯日拳硬撼五大派群雄，证明了不借神兵利器，单凭内家拳掌同样能立足武林绝巅。\n\n「气海盈满之时，一拳便是一座山。」"],
				["四 · 拳震山河", cleared_th,
					"东海海棠屿一战，他以从容步法游走八门之间，拳意通明、万法不侵，最终令千机仙子拱手认输。江湖敬称「拳震山河」，而他最常做的事，仍是回到小村与武馆师父切磋到日落。"],
			]
	var out: Array = []
	for ch in chapters:
		var unlocked: bool = bool(ch[1])
		out.append({
			"title": str(ch[0]) + ("" if unlocked else "（未解锁）"),
			"text": str(ch[2]) if unlocked else "【尚未解锁】继续在江湖历练、通关更高关卡后，茶馆老包便会为你补全这段列传。",
			"icon_kind": "", "icon_id": "",
		})
	return out
