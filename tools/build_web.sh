#!/usr/bin/env bash
# 导出网页版到 export/web/（单线程版，不需要特殊的服务器响应头，静态托管即可）
# 前提：已安装 Godot 4.4.1 及其 Web 导出模板（编辑器：项目 → 导出 → 管理导出模板）。
# 本地预览：  cd export/web && python3 -m http.server 8000   然后打开 http://localhost:8000
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf export/web
mkdir -p export/web
godot --headless --path . --import || true            # 首次需要先导入资源
godot --headless --path . --export-release "Web" export/web/index.html
ls -la export/web
