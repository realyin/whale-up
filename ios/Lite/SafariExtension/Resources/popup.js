// 弹出面板：今天刷了多久、每天的时长、今天再多看、要管的网站
async function render() {
  const s = await loadState();
  const total = todayLimit(s);
  const usedMin = Math.floor(s.used / 60);
  document.getElementById("used").textContent = `今天刷了 ${usedMin} 分钟`;
  document.getElementById("left").textContent = s.used >= total * 60
    ? `今天的 ${total} 分钟用完啦，明天凌晨 ${s.dayStartHour} 点再见～`
    : `还能刷 ${Math.ceil(total - s.used / 60)} 分钟`;
  document.getElementById("face").src = s.used >= total * 60 ? "images/head-angry.png" : "images/head-watching.png";
  document.getElementById("bar").style.width = `${Math.min(100, (s.used / (total * 60)) * 100)}%`;
  document.getElementById("limit").textContent = `${s.limit} 分钟`;
  document.getElementById("extra").textContent = s.extra === 0 ? "±0 分钟" : `${s.extra > 0 ? "+" : "−"}${Math.abs(s.extra)} 分钟`;
  document.getElementById("extraHint").textContent = `今天一共 ${total} 分钟。只管今天，明天凌晨 ${s.dayStartHour} 点自动归零。`;
  document.getElementById("reset").hidden = s.extra === 0;
  const box = document.getElementById("sites");
  if (document.activeElement !== box) box.value = s.sites.join("\n");
}

async function update(change) {
  const s = await loadState();
  change(s);
  await saveState(s);
  render();
}

document.getElementById("minus").onclick = () => update((s) => { s.limit = Math.max(5, s.limit - 5); });
document.getElementById("plus").onclick = () => update((s) => { s.limit = Math.min(240, s.limit + 5); });
// 今天的调整：每次 5 分钟；今天最少 5 分钟，最多多看 3 小时
const adjust = (m) => update((s) => { s.extra = Math.min(180, Math.max(5 - s.limit, s.extra + m)); });
document.getElementById("less").onclick = () => adjust(-5);
document.getElementById("more").onclick = () => adjust(5);
document.getElementById("reset").onclick = () => update((s) => { s.extra = 0; });
document.getElementById("sites").onchange = (e) => update((s) => {
  s.sites = e.target.value.split(/\s+/).map((x) => x.trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "")).filter(Boolean);
});
render();
