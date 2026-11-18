# 武侠幸存者（原型）

Godot 4.4 · 武侠题材 Survivor-like · 独立开发 · PC 优先

> 原型阶段：全部使用代码绘制的占位图形，用来验证玩法。招式、角色均为**原创命名**（"类"某某武学），不使用任何受版权保护的作品名称。

## 运行

1. 安装 [Godot 4.4+](https://godotengine.org/download)（标准版即可）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5。

| 操作 | 按键 |
|---|---|
| 移动（自动攻击） | WASD / 方向键 |
| 轻功（短距离无敌冲刺，耗内力） | 空格 / Shift |
| 真气爆发（耗满内力的范围大招） | E |
| 升级选择 | 1 / 2 / 3 或鼠标点击 |
| 暂停 | Esc |

## 玩法设计要点

- **内力**是核心资源：轻功和大招都耗内力，而内力 ≥ 50% 时全部伤害 +25%。
  → 逼玩家在"闪避/放大招"和"保持输出"之间取舍。
- **武学**：裂岳掌（贯穿掌风）、穿云指（穿透剑气）、回风剑（环身飞剑）。
- **心法**（被动）：纯阳诀（内力）、轻身诀（机动）、铁布衫（防御）。
- **进化**：武学满级 + 持有对应心法 → 升级时出现进化选项
  （裂岳掌+纯阳诀→亢龙破天；穿云指+轻身诀→穿云裂空；回风剑+铁布衫→回风乱舞）。
- **奇遇**：升级时 20% 概率出现高风险/高回报选项。
- **流程**：每 40 秒四周合围；4:00 Boss「海岛剑尊」登场（冲锋 + 弹幕，半血狂暴），击败即通关。

## 目录结构

```
data/game_data.json   所有数值：武学/心法/进化/奇遇/敌人（只改表，不动代码）
scripts/data.gd       Autoload：读表、注册输入、加载字体
scripts/world.gd      游戏世界：模拟 + 绘制（step(dt) 与渲染无关，可无头测试）
scripts/enemy.gd      敌人数据（RefCounted，不用 Node，便于同屏上千）
scripts/projectile.gd 弹体数据
scripts/hud.gd        HUD、菜单、升级选择、结算
scripts/main.gd       状态机 + 输入 + 相机
tests/                无头模拟测试、截图脚本
```

## 测试

```bash
# 无渲染完整局模拟（含性能统计 + Boss 流程）
godot --headless --path . res://tests/sim_test.tscn

# 真实渲染截图（需要显示或 xvfb）
SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn
```

## 字体

默认依赖系统中文字体回退。若目标机器缺中文字体，把字体放到
`assets/fonts/main.ttf`（或 `main.otf`），启动时会自动作为全局字体。

## 美术替换计划（nano banana → 像素 + 水墨）

目前所有图形都在 `world.gd` 的 `_draw_*` 里，是占位。接入 sprite 时：
- 角色/敌人：像素风，32×32 或 48×48，透明底 PNG，放入 `assets/sprites/`；
  纹理过滤已全局设为 Nearest（`project.godot`），像素不会发糊。
- 地图/特效：水墨笔触，大块背景用平铺纹理。
- 为保持同屏性能，敌人将改用 `MultiMeshInstance2D` 或 `draw_texture_rect_region` 批量绘制，
  不要给每个敌人建 `Sprite2D` 节点。
- nano banana 的角色一致性较难保证：每个角色只出"4 向待机 + 4 帧行走"，
  受击/死亡靠代码做闪白、缩放、位移。

## 已知问题 / 下一步

- 数值只经过粗略 bot 测试，真实手感需要人玩来调。
- 目前只有 1 个角色、1 张地图、1 个 Boss。
- 无音效、无存档、无局外成长（门派/江湖阅历解锁）。
