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
  document.getElementById("extraHint").textContent = `今天一共 ${total} 分钟。只管今天，明天凌晨 ${s.dayStartHour} 点自动归零。`;
  document.getElementById("reset").hidden = s.extra === 0;
  // 和 App 同步的状态：方便看出是不是连不上
  const ago = s.lastSync ? Math.round((Date.now() - s.lastSync) / 1000) : null;
  const status = document.getElementById("syncStatus");
  status.textContent = connected === undefined ? "正在和鲸醒 App 同步…"
    : connected ? "和鲸醒 App 同步：刚刚"
    : ago === null ? "还没连上鲸醒 App（Safari 这边照样计时）" : `上次和鲸醒 App 同步：${ago < 60 ? `${ago} 秒` : `${Math.round(ago / 60)} 分钟`}前`;
  document.getElementById("offline").hidden = connected !== false;
  const box = document.getElementById("sites");
  if (document.activeElement !== box) box.value = s.sites.join("\n");
}

async function update(change) {
  render(change ? await changeLocal(change) : await loadMirror());
  const synced = await sync();
  render(synced || await loadMirror(), !!synced);
}

document.getElementById("minus").onclick = () => update((s) => { s.limit = Math.max(5, s.limit - 5); s.extra = Math.max(5 - s.limit, s.extra); });
document.getElementById("plus").onclick = () => update((s) => { s.limit = Math.min(240, s.limit + 5); });
// 今天的调整：每次 5 分钟；今天最少 5 分钟，最多多看 3 小时
const adjust = (m) => update((s) => { s.extra = Math.min(180, Math.max(5 - s.limit, s.extra + m)); });
document.getElementById("less").onclick = () => adjust(-5);
document.getElementById("more").onclick = () => adjust(5);
document.getElementById("reset").onclick = () => update((s) => { s.extra = 0; });
document.getElementById("sites").onchange = (e) => update((s) => {
  s.sites = e.target.value.split(/\s+/).map((x) => x.trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "")).filter(Boolean);
});
update(null);
