// 扩展后台：把网页脚本和弹出面板的请求转给扩展的原生部分（它读写和鲸醒 App 共用的数据）。
// 直接返回 Promise（Safari 对这种写法支持得最好）；出错也回一个结果，不让对方一直等
const api = globalThis.browser ?? globalThis.chrome;

api.runtime.onMessage.addListener((msg) => {
  if (!msg || msg.to !== "native") return undefined;
  return api.runtime.sendNativeMessage("application.id", msg)
    .then((r) => r || { error: "没有回应" })
    .catch((e) => ({ error: String(e) }));
});
