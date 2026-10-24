// 鲸醒 Safari 扩展：设置和今天的用量跟鲸醒 App 共用（经扩展后台 → 原生部分 → App Group）。
// 万一连不上原生部分，就退回扩展自己的存储，照样计时。
const api = globalThis.browser ?? globalThis.chrome;

const DEFAULTS = {
  limit: 30,          // 每天一共能刷几分钟
  dayStartHour: 4,    // 一天从几点开始算，和 Mac 版一样
  sites: ["douyin.com", "bilibili.com", "b23.tv", "youtube.com", "kuaishou.com", "xiaohongshu.com",
          "weibo.com", "weibo.cn", "tiktok.com", "ixigua.com", "toutiao.com"],
  day: "", used: 0,   // 今天是哪天、今天刷了多少秒
  extraDay: "", extra: 0,  // 今天多看（正）或少看（负）几分钟，只管今天
};

/** 某个时刻算哪一天：凌晨 startHour 点以前算前一天 */
function dayKey(startHour) {
  const d = new Date(Date.now() - startHour * 3600 * 1000);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

/** 今天一共能刷几分钟（每天的时长加上今天的调整，最少 5 分钟） */
function todayLimit(s) { return Math.max(5, s.limit + s.extra); }

/** 今天一共能刷多少秒 */
function limitSeconds(s) { return todayLimit(s) * 60; }

function isWatchedSite(s, host) {
  return s.sites.some((x) => host === x || host.endsWith("." + x));
}

/**
 * 读写今天的情况。type：get / tick（seconds, site）/ adjust（minutes）/ reset / setLimit（limit）/ setSites（sites）。
 * 返回 { used, limit, extra, dayStartHour, sites }
 */
async function call(type, payload = {}) {
  try {
    const r = await api.runtime.sendMessage({ to: "native", type, ...payload });
    if (r && !r.error && typeof r.used === "number") return r;
  } catch (e) { /* 连不上原生部分：用下面的本地存储 */ }
  return callLocal(type, payload);
}

async function callLocal(type, payload) {
  const saved = (await api.storage.local.get("whaleup")).whaleup || {};
  const s = Object.assign({}, DEFAULTS, saved);
  const today = dayKey(s.dayStartHour);
  if (s.day !== today) { s.day = today; s.used = 0; }
  if (s.extraDay !== today) { s.extraDay = today; s.extra = 0; }
  if (type === "tick" && s.used < limitSeconds(s)) s.used += Math.min(30, payload.seconds || 0);
  if (type === "adjust") s.extra = Math.min(180, Math.max(5 - s.limit, s.extra + payload.minutes));
  if (type === "reset") s.extra = 0;
  if (type === "setLimit") { s.limit = Math.min(240, Math.max(5, payload.limit)); s.extra = Math.max(5 - s.limit, s.extra); }
  if (type === "setSites") s.sites = payload.sites;
  if (type !== "get") await api.storage.local.set({ whaleup: s });
  return s;
}
