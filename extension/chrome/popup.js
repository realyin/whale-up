const SCOPES = { off: "不记录内容", junk: "只记录没营养网站", all: "记录所有网页" };
const status = document.getElementById("status");
const text = document.getElementById("text");

fetch("http://127.0.0.1:47621/status", { headers: { "X-FocusGuard": "1" } })
  .then((r) => r.json())
  .then((s) => {
    status.className = "row ok";
    text.textContent = "已连接本机 App";
    document.getElementById("scope").textContent =
      `当前范围：${SCOPES[s.scope] ?? s.scope}。今天已记录 ${s.todayViews ?? 0} 条。`;
  })
  .catch(() => {
    status.className = "row bad";
    text.textContent = "连不上本机 App，请先打开专注守护";
  });

const KINDS = { subtitle: "字幕", article: "正文", description: "简介", none: "标题" };
const favButton = document.getElementById("fav");
const favStatus = document.getElementById("favStatus");
favButton.addEventListener("click", async () => {
  favButton.disabled = true;
  favStatus.textContent = "正在读取这一页…";
  const r = await chrome.runtime.sendMessage({ type: "favorite" });
  favStatus.textContent = r?.ok
    ? `已收藏（读到了${KINDS[r.kind] ?? "内容"}），正在提取要点。`
    : r?.error ?? "收藏失败";
  favButton.disabled = false;
});
