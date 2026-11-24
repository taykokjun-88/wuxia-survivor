#!/usr/bin/env bash
# 跑全部测试：后端（Node）+ 游戏逻辑（Godot 无头）。网页端到端另见 tests/e2e/run.sh（较慢，需要 playwright）。
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== 后端（Apps Script 逻辑，模拟 Google 环境）=="
node backend/test/backend.test.js
echo; echo "== 游戏（Godot 无头）=="
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . res://tests/sim_test.tscn
echo; echo "== 天赋：客户端合法的加点方案，后端也必须认 =="
godot --headless --path . res://tests/talent_dump.tscn 2>/dev/null | grep "^TALENT_CASE " | sed 's/^TALENT_CASE //' | node backend/test/talent_cross.js
