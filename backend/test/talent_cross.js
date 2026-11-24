// 运行：godot --headless --path . res://tests/talent_dump.tscn | grep ^TALENT_CASE | sed 's/^TALENT_CASE //' | node backend/test/talent_cross.js
// 客户端合法的加点方案，后端也必须认。
const { makeEnv } = require('./harness');
const lines = require('fs').readFileSync(0, 'utf8').split('\n').filter(Boolean);
const e = makeEnv({ autoConvert: false });
let bad = 0;
for (const ln of lines) {
  const c = JSON.parse(ln);
  const r = e.ctx.cleanTalents(c.t, c.level);
  if (r === null) { bad++; console.log('后端拒绝：', c.school, 'Lv' + c.level, JSON.stringify(c.t)); }
}
console.log(lines.length + ' 个方案，后端拒绝 ' + bad + ' 个');
process.exit(bad ? 1 : 0);
