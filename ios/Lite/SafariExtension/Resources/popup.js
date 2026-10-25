// 弹出面板：今天刷了多久、每天的时长、今天多看 / 少看、要管的网站。
// 改了先在本地生效，再同步给鲸醒 App；连不上 App 时下面会提示一句
function render(s, connected) {
  const total = todayLimit(s);
  const used = usedOf(s);
  document.getElementById("used").textContent = `今天刷了 ${Math.floor(used / 60)} 分钟`;
  document.getElementById("left").textContent = used >= total * 60
    ? `今天的 ${total} 分钟用完啦，明天凌晨 ${s.dayStartHour} 点再见～`
    : `还能刷 ${Math.ceil(total - used / 60)} 分钟`;
  document.getElementById("face").src = used >= total * 60 ? "images/head-angry.png" : "images/head-watching.png";
  document.getElementById("bar").style.width = `${Math.min(100, (used / (total * 60)) * 100)}%`;
  document.getElementById("limit").textContent = `${s.limit} 分钟`;
  document.getElementById("extra").textContent = s.extra === 0 ? "±0 分钟" : `${s.extra > 0 ? "+" : "−"}${Math.abs(s.extra)} 分钟`;
  document.getElementById("extraHint").textContent = `今天一共 ${total} 分钟。只管今天，明天凌晨 ${s.dayStartHour} 点自动归零。多看要输随机码，今天还剩 ${Math.max(0, 2 - (s.grants || 0))} 次。`;
  document.getElementById("reset").hidden = s.extra === 0;
  // 和 App 同步的状态：方便看出是不是连不上
  const ago = s.lastSync ? Math.round((Date.now() - s.lastSync) / 1000) : null;
  const status = document.getElementById("syncStatus");
  status.textContent = connected === undefined ? "正在和鲸醒 App 同步…"
    : connected ? "和鲸醒 App 同步：刚刚"
    : ago === null ? "还没连上鲸醒 App（Safari 这边照样计时）" : `上次和鲸醒 App 同步：${ago < 60 ? `${ago} 秒` : `${Math.round(ago / 60)} 分钟`}前`;
  document.getElementById("offline").hidden = connected !== false;
}

async function update(change) {
  render(change ? await changeLocal(change) : await loadMirror());
  const synced = await sync();
  render(synced || await loadMirror(), !!synced);
}

// ---- 随机码：放松管控（调大时长、多看、少看后恢复、删网站）要照着打一遍 ----
const ALPHABET = "ACDEFHJKMNPQRTUVWXY34679";  // 去掉了容易看混的字符
function makeCode() {
  const r = crypto.getRandomValues(new Uint32Array(20));
  const chars = [...r].map((x) => ALPHABET[x % ALPHABET.length]);
  return [0, 4, 8, 12, 16].map((i) => chars.slice(i, i + 4).join("")).join("-");
}
function drawCode(code) {
  const c = document.getElementById("gateCode");
  const g = c.getContext("2d");
  g.fillStyle = "#fffdf9"; g.fillRect(0, 0, c.width, c.height);
  g.font = "bold 34px ui-monospace, Menlo, monospace"; g.fillStyle = "#1f2b5e";
  const step = (c.width - 30) / code.length;
  [...code].forEach((ch, i) => g.fillText(ch, 15 + i * step, 54 + ((i * 7) % 5) - 2));
}
/** 输对随机码才执行 action；3 分钟内有效 */
function gate(what, action) {
  const code = makeCode();
  const started = Date.now();
  const box = document.getElementById("gate"), input = document.getElementById("gateInput"), msg = document.getElementById("gateMsg");
  document.getElementById("gateWhat").textContent = `要改的：${what}。照着打一遍这串码再决定（不能复制粘贴，3 分钟内有效）。`;
  drawCode(code);
  input.value = ""; msg.textContent = ""; box.hidden = false;
  let last = "";
  input.onpaste = (e) => { e.preventDefault(); msg.textContent = "要一个字一个字打哦"; };
  input.oninput = () => { if (input.value.length - last.length > 1) { input.value = last; msg.textContent = "要一个字一个字打哦"; } last = input.value; };
  document.getElementById("gateCancel").onclick = () => { box.hidden = true; };
  document.getElementById("gateOk").onclick = () => {
    if (Date.now() - started > 180000) { msg.textContent = "超过 3 分钟了，这串码作废了"; return; }
    const norm = (s) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (!input.value || norm(input.value) !== norm(code)) { msg.textContent = "打得不对，再看仔细一点"; return; }
    box.hidden = true;
    action();
  };
}

document.getElementById("minus").onclick = () => update((s) => { s.limit = Math.max(5, s.limit - 5); s.extra = Math.max(5 - s.limit, s.extra); });
document.getElementById("plus").onclick = async () => {
  const s = await loadMirror();
  gate(`每天从 ${s.limit} 分钟调到 ${Math.min(240, s.limit + 5)} 分钟`, () => update((m) => { m.limit = Math.min(240, m.limit + 5); }));
};
// 今天的调整：每次 5 分钟；今天最少 5 分钟，最多多看 3 小时
const adjust = (m) => update((s) => { s.extra = Math.min(180, Math.max(5 - s.limit, s.extra + m)); });
document.getElementById("less").onclick = () => adjust(-5);
// 多看：每天最多 2 次，还要输随机码；少看随时可以
const MAX_GRANTS = 2;
document.getElementById("more").onclick = async () => {
  const s = await loadMirror();
  const left = MAX_GRANTS - (s.grants || 0);
  if (left <= 0) { document.getElementById("extraHint").textContent = `今天已经多看过 ${MAX_GRANTS} 次了，不能再加了。明天见～`; return; }
  gate(`今天多看 5 分钟（今天还能多看 ${left} 次）`, () => update((m) => { m.grants = (m.grants || 0) + 1; m.extra = Math.min(180, Math.max(5 - m.limit, m.extra + 5)); }));
};
document.getElementById("reset").onclick = async () => {
  const s = await loadMirror();
  if (s.extra < 0) gate(`恢复成每天的 ${s.limit} 分钟`, () => update((m) => { m.extra = 0; }));
  else update((m) => { m.extra = 0; });
};
update(null);
