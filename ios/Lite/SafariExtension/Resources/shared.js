// 鲸醒 Safari 扩展：Safari 里刷的时间由扩展自己记（每个网站今天一共多少秒，只加不减），判断也在这边做，
// 不会因为和 App 的连接卡住、或者 App 那边没存上而停。同步时把这些“总数”发给鲸醒 App（经扩展后台 → 原生部分 → App Group），
// 拿回 App 自己记的时间（抖音等 App）和设置。发的是总数不是增量，发几次都不会多算或少算。
const api = globalThis.browser ?? globalThis.chrome;
const MIRROR = "whaleupMirror";

const DEFAULTS = {
  day: "",
  limit: 30,          // 每天一共能刷几分钟（以 App 那边为准）
  extra: 0,           // 今天多看（正）或少看（负）几分钟
  dayStartHour: 4,    // 一天从几点开始算
  sites: ["douyin.com", "bilibili.com", "b23.tv", "youtube.com", "kuaishou.com", "xiaohongshu.com",
          "weibo.com", "weibo.cn", "tiktok.com", "ixigua.com", "toutiao.com"],
  appUsed: 0,         // 上次同步时 App 自己记的秒数（抖音等 App，不含 Safari）
  web: {},            // Safari 里今天每个网站刷了多少秒（只加不减；有营养的不在这里）
  good: {},           // Safari 里今天看的有营养内容：网站 → 秒（只记下来，不算进时长）
  verdicts: {},       // AI 判断过的内容：内容 → { isJunk, category, reason }
  dirty: null,        // 在弹出面板里改了、还没同步过去的设置
  lastSync: 0,        // 上次和 App 对上的时间（毫秒）
};

/** 某个时刻算哪一天：凌晨 startHour 点以前算前一天 */
function dayKey(startHour) {
  const d = new Date(Date.now() - startHour * 3600 * 1000);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;  // 和 App 那边一样："2026-10-05"
}

/** 只认有限的数字，其他（undefined / null / NaN / 字符串）都当 fallback */
const num = (x, fallback = 0) => (typeof x === "number" && Number.isFinite(x) ? x : fallback);
/** 网站 → 秒 的账：坏掉的项去掉 */
function cleanBook(book) {
  const out = {};
  for (const [k, v] of Object.entries(book && typeof book === "object" ? book : {})) if (num(v) > 0) out[k] = num(v);
  return out;
}

async function loadMirror() {
  const saved = (await api.storage.local.get(MIRROR))[MIRROR] || {};
  const m = Object.assign({}, DEFAULTS, saved);
  // 上一版的账（nativeUsed / pending）换成这一版的写法
  if (saved.pending && !saved.web) m.web = { ...saved.pending };
  if (saved.nativeUsed !== undefined && saved.appUsed === undefined) m.appUsed = saved.nativeUsed;
  delete m.pending; delete m.nativeUsed;
  // 上一版存的日期没补零（"2026-10-5"）
  if (m.day) m.day = m.day.replace(/-(\d)(?=-|$)/g, "-0$1");
  // 存着的数字坏了（比如变成 NaN）：修回来，不然总数算出来是 NaN、永远不会锁
  m.appUsed = num(m.appUsed);
  m.limit = Math.min(240, Math.max(5, num(m.limit, 30)));
  m.extra = num(m.extra);
  m.grants = num(m.grants);
  m.dayStartHour = num(m.dayStartHour, 4);
  m.web = cleanBook(m.web);
  m.good = cleanBook(m.good);
  if (!Array.isArray(m.sites) || !m.sites.length) m.sites = DEFAULTS.sites;
  const today = dayKey(m.dayStartHour);
  if (m.day !== today) Object.assign(m, { day: today, appUsed: 0, web: {}, good: {}, extra: 0, grants: 0 });
  return m;
}

function saveMirror(m) { return api.storage.local.set({ [MIRROR]: m }); }

/** 今天一共刷了多少秒（App 和网页一起） */
function usedOf(m) { return num(m.appUsed) + Object.values(m.web || {}).reduce((a, b) => a + num(b), 0); }

/** 今天一共能刷几分钟（每天的时长加上今天的调整，最少 5 分钟） */
function todayLimit(m) { return Math.max(5, num(m.limit, 30) + num(m.extra)); }
function limitSeconds(m) { return todayLimit(m) * 60; }

function isWatchedSite(m, host) {
  return m.sites.some((x) => host === x || host.endsWith("." + x));
}

/** 在这台手机上先记下刚刷的几秒；good 为 true 时记到“有营养”里，不算时长 */
async function addLocal(site, seconds, good = false) {
  const m = await loadMirror();
  const book = good ? m.good : m.web;
  book[site] = num(book[site]) + num(seconds);
  await saveMirror(m);
  return m;
}

/** 让 AI 判断一个内容（经后台 → 原生部分 → DeepSeek）；判断过的直接用记下的。返回 {isJunk,...} / {off:true} / null */
async function judgeContent(key, info) {
  const m = await loadMirror();
  if (m.verdicts[key]) return m.verdicts[key];
  try {
    const reply = api.runtime.sendMessage({ to: "native", type: "judge", key, ...info });
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 25000));
    const r = await Promise.race([reply, timeout]);
    if (!r || r.error) return null;
    if (r.off) return { off: true };
    const now = await loadMirror();
    now.verdicts[key] = { isJunk: !!r.isJunk, category: r.category || "", reason: r.reason || "" };
    // 只留最近 300 条
    const keys = Object.keys(now.verdicts);
    for (const k of keys.slice(0, Math.max(0, keys.length - 300))) delete now.verdicts[k];
    await saveMirror(now);
    return now.verdicts[key];
  } catch (e) {
    return null;
  }
}

/** 在弹出面板里改设置：先改本地（马上生效），再同步给 App */
async function changeLocal(change) {
  const m = await loadMirror();
  change(m);
  m.dirty = { limit: m.limit, extra: m.extra, sites: m.sites, grants: m.grants || 0 };
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
      const dirty = m.dirty;
      const reply = api.runtime.sendMessage({ to: "native", type: "sync", day: m.day, web: m.web, good: m.good, settings: dirty || undefined });
      const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 2500));
      const r = await Promise.race([reply, timeout]);
      if (!r || r.error || !Number.isFinite(r.appUsed)) return null;
      // Safari 的时间以这边为准；只从 App 那边拿它自己记的时间和设置
      const now = await loadMirror();
      Object.assign(now, { appUsed: num(r.appUsed), limit: num(r.limit, now.limit), extra: num(r.extra, now.extra),
                           grants: Math.max(num(now.grants), num(r.grants)),
                           dayStartHour: num(r.dayStartHour, now.dayStartHour), sites: Array.isArray(r.sites) && r.sites.length ? r.sites : now.sites,
                           lastSync: Date.now() });
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
