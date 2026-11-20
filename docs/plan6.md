# 计划书 6：另觅机缘（Reroll）与刀客「真·霸刀破岳」（给 Claude）

适用项目：`taykokjun-88/wuxia-survivor`（分支 `claude/confident-dirac-vholjn`）

---

## 一、局内 Reroll 功能：**「另觅机缘」**

### 1. 规则设计（严格按需求，不增加额外机制）
- **功能名称**：**另觅机缘**（升级选卡界面按钮文案建议：`另觅机缘（剩余 X 次）`）。
- **次数公式**：局外等级每升 5 级，局内可用总次数 `+3`：
  - `rerolls_total = int(Save.meta_level / 5) * 3`
  - 示例：Lv 1–4 为 `0` 次；Lv 5–9 为 `3` 次；Lv 10–14 为 `6` 次，以此类推。
- **行为**：仅在升级选卡界面点击「另觅机缘」时消耗 1 次次数，重新抽取 3 张升级卡（不消耗当前升级机会，不加锁定/禁用/花钱刷新等额外功能）。

### 2. 实现要点
- **`scripts/world.gd`**：
  - 新增状态变量 `rerolls_left: int = 0`。
  - 在 `start_run(...)` 初始化：`rerolls_left = int(Save.meta_level / 5) * 3`。
  - 提供方法 `can_reroll() -> bool` 与 `use_reroll() -> Array`（扣减 `rerolls_left -= 1` 并调用 `roll_choices(3)` 返回新候选）。
- **`scripts/hud.gd`**：
  - 在 `_build_levelup()` 的 3 张选卡下方新增「另觅机缘」按钮（古铜色描边风格，与选卡协调）。
  - 在 `show_choices()` 时更新按钮文本与状态：`rerolls_left > 0` 时可点击并显示 `另觅机缘（剩余 %d 次）`，`rerolls_left <= 0` 时禁用按钮（`disabled = true`，显示 `另觅机缘（已用尽）`）。
  - 点击后调用 `w.use_reroll()` 并重新 `show_choices(new_choices, current_title)`。
- **`tests/sim_test.gd`**：
  - 验证 `meta_level` 为 `4 / 5 / 10` 时，`rerolls_left` 分别为 `0 / 3 / 6`。
  - 验证 `use_reroll()` 会扣减次数，归零后 `can_reroll()` 返回 `false`。

---

## 二、刀客专属机制：**「真·霸刀破岳」**

### 1. 触发与冷却规则
- **适用流派**：仅刀客（`school_id == "blade"`）。
- **触发条件**：当前气血降至 `<= max_hp * 0.20`（20%），且当前未处于「真·霸刀破岳」状态、内置冷却已归零（`true_blade_t <= 0.0 and true_blade_cd <= 0.0`）。
- **持续时间**：**10.0 秒**（`true_blade_t = 10.0`）。
- **内置冷却**：**30.0 秒**。**注意：这 30 秒冷却必须在 10 秒「真·霸刀破岳」状态完全结束后才开始倒计时**（即 `true_blade_t` 从 10 降到 0 的那一刻，才设置 `true_blade_cd = 30.0` 并开始递减）。

### 2. 10 秒状态内效果
1. **刀招无任何消耗**：
   - `scripts/skills/blade_skills.gd` 的 `pay_hp()` 开头判断：`if w.true_blade_t > 0.0: return`（期间 `血刀经`、`燃木`、`玄虚`、`屠龙` 均 0 耗血）。
2. **三项回复临时双倍（`× 2.0`）**：
   - 定义辅助倍率 `var heal_mult := 2.0 if true_blade_t > 0.0 else 1.0`（或由 `Data.T("true_blade_heal_mult")` 读取）。
   - **击杀回血**（`kill_hp`）：`_kill()` 中计算击杀回血时乘以 `heal_mult`。
   - **命中吸血**：`hit_enemy()` 中 `sk.mods["heal"]` 计算回复及单次上限（`0.6 * heal_mult`）均乘以 `heal_mult`；`blade_skills.gd` 中 `XueDao` 自带吸血及上限同理乘以 `heal_mult`。
   - **自身回血**：`world.gd` 中 `hp_regen` 与 `full_hp_regen` 每帧/每秒恢复结算时乘以 `heal_mult`。
3. **身体光效 Aura 与 HUD 提示**：
   - **`scripts/world.gd`（`_draw_player()`）**：当 `true_blade_t > 0.0` 时，在玩家脚底与周身绘制赤红 + 耀金双色脉动光环（`draw_circle` / `draw_arc` 叠加随 `time` 呼吸缩放的透明光晕与刀气微粒），让玩家一眼看出霸体/免耗吸血期已开启。
   - **`scripts/hud.gd`**：在屏幕下方居中的刀魂条上方或条内文字处，当 `true_blade_t > 0.0` 时优先高亮提示 `真·霸刀破岳！免耗·双倍回复 %.1fs`；冷却中可按需在旁显示小字 `破岳冷却 %ds`。

### 3. 数据与测试要点
- **`data/game_data.json`**：在全局调优参数中新增：
  - `"true_blade_hp_pct": 0.20`
  - `"true_blade_dur": 10.0`
  - `"true_blade_cd": 30.0`
  - `"true_blade_heal_mult": 2.0`
- **`tests/sim_test.gd`**：
  - 模拟刀客血量降至 20% 时触发 `true_blade_t == 10.0`，验证期间 `pay_hp()` 不扣血、击杀回血 / 吸血 / 自身回血均为正常值的 2 倍。
  - 验证 10 秒结束后 `true_blade_cd` 才开始从 `30.0` 倒计时；冷却未结束前即使血量仍在 20% 以下也不会再次触发；30 秒冷却归零后若血量仍在 20% 以下可再次触发。

---

## 三、交付要求
- 实装完成后运行 `tests/sim_test.gd` 确保全部测试通过。
- 同步更新 `docs/status.md` 留下本次更新记录。
