// 弹出面板：今天刷了多久、和 App 的同步状态，以及“把这个网站加入管控”。
// 时间设置（每天多久、今天多看少看）和删网站都只在鲸醒 App 里改
function render(s, connected) {
  const total = todayLimit(s);
  const used = usedOf(s);
  document.getElementById("used").textContent = `今天刷了 ${Math.floor(used / 60)} 分钟`;
  document.getElementById("left").textContent = used >= total * 60
    ? `今天的 ${total} 分钟用完啦，明天凌晨 ${s.dayStartHour} 点再见～`
    : `今天一共 ${total} 分钟，还能刷 ${Math.ceil(total - used / 60)} 分钟`;
  document.getElementById("face").src = used >= total * 60 ? "images/head-angry.png" : "images/head-watching.png";
  document.getElementById("bar").style.width = `${Math.min(100, (used / (total * 60)) * 100)}%`;
  const ago = s.lastSync ? Math.round((Date.now() - s.lastSync) / 1000) : null;
  document.getElementById("syncStatus").textContent = connected === undefined ? "正在和鲸醒 App 同步…"
    : connected ? "和鲸醒 App 同步：刚刚"
    : ago === null ? "还没连上鲸醒 App（Safari 这边照样计时）" : `上次和鲸醒 App 同步：${ago < 60 ? `${ago} 秒` : `${Math.round(ago / 60)} 分钟`}前`;
  document.getElementById("offline").hidden = connected !== false;
  renderSite(s);
}

// ---- 把当前网站加进管控 ----
let currentSite = null;

/** 当前标签页的网站：去掉 www. 和 m. */
async function findSite() {
  try {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    const host = new URL(tab.url).hostname.toLowerCase();
    if (!host.includes(".")) return null;
    return host.replace(/^(www|m)\./, "");
  } catch (e) {
    return null;
  }
}

function renderSite(s) {
  const card = document.getElementById("addCard");
  if (!currentSite) { card.hidden = true; return; }
  card.hidden = false;
  document.getElementById("site").textContent = currentSite;
  const listed = s.sites.find((x) => currentSite === x || currentSite.endsWith("." + x));
  const whole = listed && (s.wholeSites || []).includes(listed);
  document.getElementById("addContent").hidden = !!listed;
  document.getElementById("addWhole").hidden = !!whole;
  document.getElementById("siteState").textContent = !listed ? "" : whole ? `已经在管了（${listed}，整站管）` : `已经在管了（${listed}，按内容管）`;
}

/** 加入名单（或改成整站管）：先改本地，马上生效；再告诉鲸醒 App */
async function addSite(whole) {
  const m = await loadMirror();
  const listed = m.sites.find((x) => currentSite === x || currentSite.endsWith("." + x)) || currentSite;
  if (!m.sites.includes(listed)) m.sites.push(listed);
  if (whole && !(m.wholeSites || []).includes(listed)) (m.wholeSites ||= []).push(listed);
  await saveMirror(m);
  render(m, undefined);
  try {
    await api.runtime.sendMessage({ to: "native", type: "addSite", site: listed, whole });
  } catch (e) { /* 连不上 App：这边已经生效，下次同步时 App 那边的名单为准，所以提示打开一次 App */ }
  const synced = await sync();
  render(synced || await loadMirror(), !!synced);
  document.getElementById("siteState").textContent += "　刷新一下网页就生效";
}

document.getElementById("addContent").onclick = () => addSite(false);
document.getElementById("addWhole").onclick = () => addSite(true);

(async () => {
  currentSite = await findSite();
  render(await loadMirror(), undefined);
  const synced = await sync();
  render(synced || await loadMirror(), !!synced);
})();
