// 鲸醒 Safari 扩展：先在扩展自己的存储里记账、判断（不会因为和 App 的连接卡住而停），
// 再顺带把没同步的秒数和改过的设置发给鲸醒 App（经扩展后台 → 原生部分 → App Group），拿回 App 那边的总时长和设置。
const api = globalThis.browser ?? globalThis.chrome;
const MIRROR = "whaleupMirror";

const DEFAULTS = {
  day: "",
  limit: 30,          // 每天一共能刷几分钟（以 App 那边为准）
  extra: 0,           // 今天多看（正）或少看（负）几分钟
  dayStartHour: 4,    // 一天从几点开始算
  sites: ["douyin.com", "bilibili.com", "b23.tv", "youtube.com", "kuaishou.com", "xiaohongshu.com",
          "weibo.com", "weibo.cn", "tiktok.com", "ixigua.com", "toutiao.com"],
  nativeUsed: 0,      // 上次同步时 App 那边今天的总秒数（App 和已经同步过去的网页时间）
  pending: {},        // 还没同步过去的网页秒数：网站 → 秒
  dirty: null,        // 在弹出面板里改了、还没同步过去的设置
};

/** 某个时刻算哪一天：凌晨 startHour 点以前算前一天 */
function dayKey(startHour) {
  const d = new Date(Date.now() - startHour * 3600 * 1000);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

async function loadMirror() {
  const saved = (await api.storage.local.get(MIRROR))[MIRROR] || {};
  const m = Object.assign({}, DEFAULTS, saved);
  const today = dayKey(m.dayStartHour);
  if (m.day !== today) Object.assign(m, { day: today, nativeUsed: 0, pending: {}, extra: 0 });
  return m;
}

function saveMirror(m) { return api.storage.local.set({ [MIRROR]: m }); }

/** 今天一共刷了多少秒（App 和网页一起） */
function usedOf(m) { return m.nativeUsed + Object.values(m.pending).reduce((a, b) => a + b, 0); }

/** 今天一共能刷几分钟（每天的时长加上今天的调整，最少 5 分钟） */
function todayLimit(m) { return Math.max(5, m.limit + m.extra); }
function limitSeconds(m) { return todayLimit(m) * 60; }

function isWatchedSite(m, host) {
  return m.sites.some((x) => host === x || host.endsWith("." + x));
}

/** 在这台手机上先记下刚刷的几秒 */
async function addLocal(site, seconds) {
  const m = await loadMirror();
  m.pending[site] = (m.pending[site] || 0) + seconds;
  await saveMirror(m);
  return m;
}

/** 在弹出面板里改设置：先改本地（马上生效），再同步给 App */
async function changeLocal(change) {
  const m = await loadMirror();
  change(m);
  m.dirty = { limit: m.limit, extra: m.extra, sites: m.sites };
  await saveMirror(m);
  return m;
}

let syncing = null;
/** 和 App 同步一次；2.5 秒没回音就算了，下次再来。成功返回新的本地账，失败返回 null */
function sync() {
  if (syncing) return syncing;
  syncing = (async () => {
    try {
      const m = await loadMirror();
      const sent = { ...m.pending };
      const dirty = m.dirty;
      const reply = api.runtime.sendMessage({ to: "native", type: "sync", web: sent, settings: dirty || undefined });
      const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 2500));
      const r = await Promise.race([reply, timeout]);
      if (!r || r.error || typeof r.used !== "number") return null;
      // 等回音的时候可能又记了几秒：只扣掉这次发过去的
      const now = await loadMirror();
      for (const [site, secs] of Object.entries(sent)) {
        const left = (now.pending[site] || 0) - secs;
        if (left > 0.5) now.pending[site] = left; else delete now.pending[site];
      }
      Object.assign(now, { nativeUsed: r.used, limit: r.limit, extra: r.extra, dayStartHour: r.dayStartHour, sites: r.sites });
      if (dirty && JSON.stringify(now.dirty) === JSON.stringify(dirty)) now.dirty = null;
      await saveMirror(now);
      return now;
    } catch (e) {
      return null;
    } finally {
      syncing = null;
    }
  })();
  return syncing;
}
