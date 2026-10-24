// 扩展后台：把网页脚本和弹出面板的请求转给扩展的原生部分（它读写和鲸醒 App 共用的数据）
const api = globalThis.browser ?? globalThis.chrome;

api.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.to !== "native") return;
  api.runtime.sendNativeMessage("application.id", msg)
    .then((r) => sendResponse(r || { error: "没有回应" }))
    .catch((e) => sendResponse({ error: String(e) }));
  return true; // 异步回复
});
