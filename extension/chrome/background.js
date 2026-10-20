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

async function askPage(tabId) {
  try {
    return await chrome.tabs.sendMessage(tabId, { type: "extract" });
  } catch {
    return null;
  }
}

// 收藏当前页面：让页面脚本提取字幕 / 正文，再交给本机 App 提炼要点
async function favoriteActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return { ok: false, error: "没有可以收藏的页面" };
  if (!/^https?:/.test(tab.url || "https:")) return { ok: false, error: "这个页面不能收藏（只支持网页）" };
  let page = await askPage(tab.id);
  if (!page) {
    // 扩展更新前就打开的页面里没有新版脚本：注入一份再试
    try {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
      page = await askPage(tab.id);
    } catch {
      // 浏览器内部页面、应用商店等不允许注入
    }
  }
  if (!page) return { ok: false, error: "读不到这个页面的内容，刷新页面后再试" };
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
