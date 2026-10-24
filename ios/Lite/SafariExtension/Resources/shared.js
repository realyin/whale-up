// 鲸醒 Safari 扩展：设置和今天的用量都存在扩展自己的存储里（免费版不和 App 共享）
const api = globalThis.browser ?? globalThis.chrome;

const DEFAULTS = {
  limit: 30,          // 每天在这些网站上一共能刷几分钟
  dayStartHour: 4,    // 一天从几点开始算，和 Mac 版一样
  sites: ["douyin.com", "bilibili.com", "b23.tv", "youtube.com", "kuaishou.com", "xiaohongshu.com",
          "weibo.com", "weibo.cn", "tiktok.com", "ixigua.com", "toutiao.com"],
  day: "", used: 0,   // 今天是哪天、今天刷了多少秒
  extraDay: "", extra: 0,  // 今天手动加的分钟
};

/** 某个时刻算哪一天：凌晨 dayStartHour 点以前算前一天 */
function dayKey(startHour) {
  const d = new Date(Date.now() - startHour * 3600 * 1000);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

async function loadState() {
  const saved = (await api.storage.local.get("whaleup")).whaleup || {};
  const s = Object.assign({}, DEFAULTS, saved);
  const today = dayKey(s.dayStartHour);
  if (s.day !== today) { s.day = today; s.used = 0; }
  if (s.extraDay !== today) { s.extraDay = today; s.extra = 0; }
  return s;
}

function saveState(s) { return api.storage.local.set({ whaleup: s }); }

/** 今天一共能刷多少秒 */
function limitSeconds(s) { return (s.limit + s.extra) * 60; }

function isWatchedSite(s, host) {
  return s.sites.some((x) => host === x || host.endsWith("." + x));
}
