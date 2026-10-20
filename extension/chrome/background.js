// 内容脚本不能直接访问 127.0.0.1（受网页跨域限制），统一由后台转发给本机 App。
const ENDPOINT = "http://127.0.0.1:47621";

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg?.type !== "views") return;
  fetch(`${ENDPOINT}/views`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-FocusGuard": "1" },
    body: JSON.stringify(msg.views),
  })
    .then((r) => reply({ ok: r.ok }))
    .catch(() => reply({ ok: false })); // App 没开时静默丢弃
  return true; // 异步回复
});

// 收藏当前页面：让页面脚本提取字幕 / 正文，再交给本机 App 提炼要点
async function favoriteActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return { ok: false, error: "没有可以收藏的页面" };
  let page;
  try {
    page = await chrome.tabs.sendMessage(tab.id, { type: "extract" });
  } catch {
    return { ok: false, error: "这个页面读不到内容，刷新页面后再试" };
  }
  try {
    const r = await fetch(`${ENDPOINT}/favorites`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-FocusGuard": "1" },
      body: JSON.stringify(page),
    });
    return r.ok ? { ok: true, kind: page.textKind } : { ok: false, error: "App 没有接收，请检查专注守护是否在运行" };
  } catch {
    return { ok: false, error: "连不上本机 App，请先打开专注守护" };
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg?.type !== "favorite") return;
  favoriteActiveTab().then(reply);
  return true;
});

chrome.commands?.onCommand.addListener((command) => {
  if (command === "favorite") favoriteActiveTab();
});
