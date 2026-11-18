#!/usr/bin/env bash
# 一键网页端到端测试：构建网页 → 启动静态服务器(8077) + 模拟后端(8099) → 跑 Chromium 流程 → 清理
set -euo pipefail
cd "$(dirname "$0")/../.."
tools/build_web.sh > /dev/null
(cd export/web && python3 -m http.server 8077 > /tmp/e2e_http.log 2>&1 & echo $! > /tmp/e2e_http.pid)
node backend/test/mock_server.js 8099 > /tmp/e2e_mock.log 2>&1 & echo $! > /tmp/e2e_mock.pid
trap 'kill $(cat /tmp/e2e_http.pid /tmp/e2e_mock.pid) 2>/dev/null || true' EXIT
sleep 2
NODE_PATH=${NODE_PATH:-$(npm root -g)} node tests/e2e/web_e2e.js
