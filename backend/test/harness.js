// 模拟 Google Apps Script 环境，让 Code.gs 能在 Node 里跑。
// 可选的"表格自作聪明"模式：把 ISO 时间字符串转成 Date、把纯数字字符串转成数字（除非该列设为纯文本）。
const vm = require('vm');
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');

const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

class MockSheet {
  constructor(name, opts) { this.name = name; this.data = []; this.frozen = 0; this.textCols = new Set(); this.opts = opts; }
  _coerce(v, col) {
    if (!this.opts.autoConvert || typeof v !== 'string') return v;
    if (ISO_RE.test(v)) return new Date(v);                          // 表格会把它变成日期
    if (!this.textCols.has(col) && /^\d+(\.\d+)?$/.test(v)) return Number(v);   // 纯数字变数字（丢前导 0）
    return v;
  }
  getName() { return this.name; }
  getLastRow() { return this.data.length; }
  getMaxRows() { return 1000; }
  getRange(r, c, nr = 1, nc = 1) {
    const self = this;
    return {
      getValues() {
        const out = [];
        for (let i = 0; i < nr; i++) {
          const row = self.data[r - 1 + i] || [];
          out.push(Array.from({ length: nc }, (_, j) => (row[c - 1 + j] === undefined ? '' : row[c - 1 + j])));
        }
        return out;
      },
      setValues(vals) {
        vals.forEach((rowVals, i) => {
          const ri = r - 1 + i;
          self.data[ri] = self.data[ri] || [];
          rowVals.forEach((v, j) => { self.data[ri][c - 1 + j] = ri === 0 ? v : self._coerce(v, c + j); });
        });
      },
      setValue(v) { const ri = r - 1; self.data[ri] = self.data[ri] || []; self.data[ri][c - 1] = ri === 0 ? v : self._coerce(v, c); },
      setNumberFormat(f) { if (f === '@') self.textCols.add(c); },
    };
  }
  appendRow(arr) { this.data.push(arr.map((v, j) => this._coerce(v, j + 1))); }
  setFrozenRows(n) { this.frozen = n; }
  deleteRows(start, n) { this.data.splice(start - 1, n); }
}

function makeEnv(opts = {}) {
  const sheets = {};
  const ui = { queue: [], alerts: [], yes: true };
  let clock = 1_800_000_000_000;
  const ctx = {
    console,
    Math, JSON, Date, Number, String, Object, Array, RegExp, isFinite, parseInt, parseFloat, Error,
    Utilities: {
      DigestAlgorithm: { SHA_256: 'SHA_256' }, Charset: { UTF_8: 'UTF_8' },
      computeDigest: (algo, text) => Array.from(crypto.createHash('sha256').update(text, 'utf8').digest()).map((b) => (b > 127 ? b - 256 : b)),
      getUuid: () => crypto.randomUUID(),
    },
    ContentService: {
      MimeType: { JSON: 'JSON' },
      createTextOutput: (text) => ({ text, setMimeType() { return this; } }),
    },
    LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
    SpreadsheetApp: {
      getActiveSpreadsheet: () => ({
        getSheetByName: (n) => sheets[n] || null,
        insertSheet: (n) => (sheets[n] = new MockSheet(n, opts)),
      }),
      getUi: () => ({
        ButtonSet: { OK_CANCEL: 'OK_CANCEL', YES_NO: 'YES_NO' },
        Button: { OK: 'OK', YES: 'YES' },
        prompt: () => { const v = ui.queue.shift(); return { getSelectedButton: () => (v === null ? 'CANCEL' : 'OK'), getResponseText: () => v || '' }; },
        alert: (m) => { ui.alerts.push(m); return ui.yes ? 'YES' : 'NO'; },
        createMenu: () => ({ addItem() { return this; }, addSeparator() { return this; }, addToUi() {} }),
      }),
    },
  };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Code.gs'), 'utf8'), ctx);
  ctx.__clock = clock;
  vm.runInContext('now = function () { return __clock; };', ctx);   // 可控时钟
  return {
    ctx, sheets, ui,
    advance(ms) { ctx.__clock += ms; },
    time() { return ctx.__clock; },
    call(req) { return JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify(req) } }).text); },
    get(params) { return JSON.parse(ctx.doGet({ parameter: params }).text); },
    sheetRows(key) { return (sheets[ctx.SHEETS[key]] || { data: [] }).data; },
    invite(code, name, active = true, max = 0) {
      ctx.setup();
      sheets[ctx.SHEETS.invites].appendRow([code, name, active, new Date(ctx.__clock).toISOString(), max, 0, '']);
    },
  };
}

module.exports = { makeEnv };
