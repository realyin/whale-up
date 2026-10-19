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
