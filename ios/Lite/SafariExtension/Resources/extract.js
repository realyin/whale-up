// 从网页里取出视频的标题、作者、标签、简介（给 AI 判断用）。规则和 Mac 版 Chrome 扩展一样，
// 另外加了手机版网页（m.bilibili.com、m.youtube.com 等）的兜底：取不到就用网页标题和分享信息
const GENERIC_TAGS = new Set(["哔哩哔哩", "bilibili", "B站", "弹幕", "抖音", "douyin", "YouTube"]);
const meta = (name) =>
  document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content?.trim() || "";
const text = (selector) => document.querySelector(selector)?.innerText?.trim() || "";
const clip = (s, n) => (s || "").replace(/\s+/g, " ").trim().slice(0, n);
const MIN_VIDEO_AREA = 40000; // 太小的（预览图、广告）不算

/**
 * 正在看的视频：屏幕上露出来最多的那个，在播的优先。可以上下划的视频流（推特、抖音）会提前加载下一条，
 * 那条在屏幕外，不能按“最大”去挑
 */
function largestVideo() {
  let best = null;
  let bestScore = 0;
  for (const v of document.querySelectorAll("video")) {
    const r = v.getBoundingClientRect();
    if (r.width * r.height < MIN_VIDEO_AREA) continue;
    const w = Math.min(r.right, window.innerWidth) - Math.max(r.left, 0);
    const h = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
    const shown = w > 0 && h > 0 ? w * h : 0;
    // 都不在屏幕上时（少见）退回按大小挑
    const score = shown > 0 ? shown + (v.paused ? 0 : 1e7) : r.width * r.height * 1e-6;
    if (score > bestScore) { best = v; bestScore = score; }
  }
  return best;
}

/** 正在看的推文：全屏看视频（mediaViewer）时网址里有 currentTweet / currentTweetUser，以它为准；否则是网址里的那条 */
function tweetRef() {
  const q = new URLSearchParams(location.search);
  const id = q.get("currentTweet"), user = q.get("currentTweetUser");
  if (id && user) return { user, id, viewer: true };
  const m = location.pathname.match(/^\/([^/]+)\/status\/(\d+)/);
  return m ? { user: m[1], id: m[2], viewer: false } : null;
}

/** 推特视频的“指纹”：封面图里带着这个视频自己的编号，划到下一条时会变（网址不一定变） */
function videoMark(video) {
  if (!video) return "";
  const poster = video.poster || video.getAttribute("poster") || "";
  const id = poster.match(/(?:video_thumb|_video_thumb|tweet_video_thumb)\/(\d+)/);
  if (id) return id[1];
  if (poster) return poster.split("?")[0];
  return (video.currentSrc || video.src || "").split("?")[0];
}

/**
 * 这个视频所在的那条推文：视频在某条推文（article）里就是它；全屏看视频时不在 article 里，
 * 就往外层找离视频最近、而且文字真的露在屏幕上的那一层（别找到垫在下面的时间线）
 */
function tweetBox(video) {
  const article = video?.closest("article");
  if (article) return { box: article, onScreen: false };
  let el = video;
  for (let i = 0; el && i < 12; i++, el = el.parentElement) {
    if ([...el.querySelectorAll('[data-testid="tweetText"]')].some(isOnTop)) return { box: el, onScreen: true };
  }
  return null;
}

/** 从视频往外层找，取离它最近的匹配元素文字（信息流里每个视频各有一份描述） */
function nearText(video, selectors) {
  let el = video;
  for (let i = 0; el && i < 12; i++, el = el.parentElement) {
    for (const s of selectors) {
      const t = el.querySelector(s)?.innerText?.trim();
      if (t) return t;
    }
  }
  return "";
}

function extract(video) {
  const host = location.hostname;
  const d = { title: "", author: "", tags: [], description: "" };

  if (host.endsWith("bilibili.com")) {
    d.title = text("h1.video-title") || text(".video-title") || text("h1");
    d.author = text(".up-name") || text(".author-name");
    d.tags = [...document.querySelectorAll(".tag-link")].map((a) => a.innerText);
    d.description = text(".desc-info-text");
  } else if (host.endsWith("douyin.com")) {
    if (video) {
      d.title = nearText(video, ['[data-e2e="video-desc"]']);
      d.author = nearText(video, ['[data-e2e="feed-video-nickname"]', '[data-e2e="video-author-title"]']);
    }
    d.title = d.title.replace(/\s*(展开|收起)\s*$/, "");
    d.author = d.author.replace(/^@/, "");
    d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
  } else if (host === "x.com" || host.endsWith(".x.com") || host.endsWith("twitter.com")) {
    const ref = tweetRef();
    if (ref?.viewer) {
      // 全屏看视频（/mediaViewer）：往下划时网址前半段一直是点进来的那条，正在看的是 currentTweet 参数里的那条。
      // 屏幕上的作者对得上才用屏幕上的字（刚划过去时文字可能还没换）；对不上就留空，等一会儿再读或交给 App 去推特接口要
      d.tweet = `https://x.com/${ref.user}/status/${ref.id}`;
      const who = shownText('[data-testid="User-Name"]');
      if (!who || who.toLowerCase().includes("@" + ref.user.toLowerCase())) {
        d.title = shownText('[data-testid="tweetText"], div[lang][dir="auto"]');
        d.author = who.split("\n").slice(0, 2).join(" ");
      }
      d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
      return finish(d);
    }
    // 先认视频旁边的那条推文：全屏看视频时可以一直往下划，网址停在第一条，视频和文字早换了
    const near = video && tweetBox(video);
    if (near) {
      const pick = (sel) => near.onScreen ? shownText(sel, near.box) : (near.box.querySelector(sel)?.innerText?.trim() || "");
      d.title = pick('[data-testid="tweetText"]');
      d.author = pick('[data-testid="User-Name"]').split("\n").slice(0, 2).join(" ");
      const link = near.box.querySelector('a[href*="/status/"]')?.getAttribute("href")?.match(/^\/([^/]+)\/status\/(\d+)/);
      if (link) d.tweet = `https://x.com/${link[1]}/status/${link[2]}`;
    }
    // 点开的那条：页面上可能还垫着时间线（手机上全屏看视频时），按网址里的推文编号找，不能直接取第一条
    const id = (location.pathname.match(/\/status\/(\d+)/) || [])[1];
    const articles = [...document.querySelectorAll('article[data-testid="tweet"], article')];
    // 没有编号就是第一条；有编号却找不到，不能拿第一条凑数（多半是垫在下面的时间线），留空让 App 去推特接口要
    const tweet = id ? articles.find((a) => a.querySelector(`a[href*="/status/${id}"]`)) : articles[0];
    // 推文网址：网页上取不到文字时，App 拿它去推特公开接口要文字
    const user = (location.pathname.match(/^\/([^/]+)\/status\//) || [])[1];
    // 视频旁边找到了自己那条就不再按网址找（网址可能还是划进来时的第一条）
    if (!d.tweet && !d.title) {
      d.title = tweet?.querySelector('[data-testid="tweetText"]')?.innerText?.trim() || "";
      if (id && user) d.tweet = `https://x.com/${user}/status/${id}`;
      d.author = (tweet?.querySelector('[data-testid="User-Name"]')?.innerText || "").split("\n").slice(0, 2).join(" ");
    }
    // 手机上全屏看视频（/mediaViewer）时推文文字不在 article 里：取屏幕上真正露在最上面的那段推文文字
    // （垫在下面的时间线被盖住了，不算）。敏感内容的推文，推特公开接口不给，只能从这里读
    if (!d.title) d.title = shownText('[data-testid="tweetText"], div[lang][dir="auto"]');
    if (!d.author) d.author = shownText('[data-testid="User-Name"]').split("\n").slice(0, 2).join(" ");
    // 取不到时用网页标题：推文页的标题就是“某某 在 X 上：“推文内容” / X”
    // 网页标题是网址里那条的：只有视频就是那条（或者认不出是哪条）时才用
    if (!d.title && (!d.tweet || (id && d.tweet.endsWith("/status/" + id)))) {
      const m = document.title.match(/^(.*?)\s*(?:在 X 上|on X)\s*[:：]\s*[“"](.*)[”"]\s*\/\s*X$/s);
      if (m) { d.title = m[2].trim(); d.author ||= m[1].trim(); }
    }
    d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
  } else if (host.endsWith("youtube.com")) {
    // 单页应用：划到下一个视频时，上一个的标题区还藏在页面里。优先用 oEmbed 接口要到的（youtubeInfo），
    // 页面元素只在对应的页面上读（长视频页读长视频的标题区）
    const info = ytInfo.get(youtubeId());
    if (info) { d.title = info.title; d.author = info.author; }
    else if (location.pathname === "/watch") {
      d.title = text("h1.ytd-watch-metadata") || text(".slim-video-metadata-header h2");
      d.author = text("#owner #channel-name a") || text(".slim-owner-channel-name");
    }
    d.title ||= document.title.replace(/^\(\d+\)\s*/, "");
    d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
  }

  // 推文没取到文字：别拿“X”这种网页标题凑数，留空交给 App
  if (!d.tweet || d.title) d.title ||= meta("og:title") || document.title;
  // 单页应用里 meta 不跟着换，别拿上一个视频的简介凑
  if (!host.endsWith("youtube.com")) {
    d.author ||= meta("author");
    if (!d.tags.length) d.tags = meta("keywords").split(/[,，]/);
    d.description ||= meta("og:description") || meta("description");
  }

  return finish(d);
}

/** 统一收尾：去掉网站后缀、标签去重、截短 */
function finish(d) {
  d.title = clip(d.title.replace(/_哔哩哔哩_bilibili$/, "").replace(/ - YouTube$/, ""), 200);
  d.tags = [...new Set(d.tags.map((t) => clip(t, 30)))]
    .filter((t) => t && t !== d.title && !GENERIC_TAGS.has(t))
    .slice(0, 12);
  d.description = clip(d.description, 500);
  d.author = clip(d.author, 80);
  return d;
}

/** YouTube 视频编号（Shorts 或长视频页），别的页面返回 null */
function youtubeId() {
  if (!location.hostname.endsWith("youtube.com")) return null;
  const p = location.pathname;
  if (p.startsWith("/shorts/")) return p.split("/")[2] || null;
  if (p === "/watch") return new URLSearchParams(location.search).get("v");
  return null;
}

/** 按编号向 YouTube 的 oEmbed 接口要标题和作者（同一个网站，不用登录），最多等 3 秒；要到的记在 ytInfo 里 */
const ytInfo = new Map();
async function youtubeInfo(id) {
  if (!id) return null;
  if (ytInfo.has(id)) return ytInfo.get(id);
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 3000);
    const r = await fetch(`/oembed?format=json&url=${encodeURIComponent("https://www.youtube.com/watch?v=" + id)}`, { signal: ctrl.signal });
    clearTimeout(timer);
    const j = r.ok ? await r.json() : null;
    if (!j) return null;
    const info = { title: j.title || "", author: j.author_name || "" };
    ytInfo.set(id, info);
    return info;
  } catch (e) {
    return null;
  }
}

/** 屏幕上露在最上层（没被别的东西盖住）的第一个匹配元素的文字 */
function shownText(selector, root = document) {
  for (const el of root.querySelectorAll(selector)) {
    const text = (el.innerText || "").trim();
    if (text && isOnTop(el)) return text;
  }
  return "";
}

/** 这个元素在屏幕上、没被别的东西盖住 */
function isOnTop(el) {
  const r = el.getBoundingClientRect();
  if (r.width < 1 || r.height < 1 || r.bottom <= 0 || r.top >= window.innerHeight) return false;
  const x = Math.min(window.innerWidth - 1, Math.max(0, r.left + Math.min(20, r.width / 2)));
  const y = Math.min(window.innerHeight - 1, Math.max(0, r.top + Math.min(10, r.height / 2)));
  const hit = document.elementFromPoint(x, y);
  return !!hit && (hit === el || el.contains(hit));
}

/** 什么时候算“换了一个内容”：网址变了；抖音信息流网址不变，按视频描述 / 片源区分 */
function identity(video) {
  const url = location.href.split("#")[0];
  // 推特：/用户/status/编号/video/1 和 /用户/status/编号 是同一条。全屏看视频时正在看的是 currentTweet 参数里那条；
  // 普通推文页再加上视频自己的指纹（同一页里划到别的视频时网址可能不变）
  const ref = tweetRef();
  if (ref?.viewer) return `${location.origin}/${ref.user}/status/${ref.id}`;
  const tweet = location.pathname.match(/^\/[^/]+\/status\/\d+/);
  if (tweet) return location.origin + tweet[0] + (video ? "|" + videoMark(video) : "");
  if (location.hostname.endsWith("douyin.com") && video) {
    const desc = nearText(video, ['[data-e2e="video-desc"]']);
    return url + "|" + (desc || (video.currentSrc || "").split("?")[0]);
  }
  return url;
}

/**
 * 视频网站上“逛”的页面：首页、搜索、个人主页……额度用完以后也不锁，不然连找有营养的视频都没法找。
 * 抖音、快手、TikTok 的首页就是自动播放的视频流，不算。（和 Mac 版 PageKind.isBrowsePage 是同一套规则）
 */
function isBrowsePage(href = location.href) {
  let u;
  try { u = new URL(href); } catch (e) { return false; }
  const host = u.hostname.toLowerCase();
  const path = (u.pathname || "/").toLowerCase();
  const on = (d) => host === d || host.endsWith("." + d);
  const starts = (list) => list.some((p) => path.startsWith(p));

  if (on("bilibili.com")) {
    if (host.startsWith("search.") || host.startsWith("space.") || host.startsWith("t.")) return true;
    if (starts(["/video/", "/bangumi/", "/cheese/", "/list/", "/festival/"])) return false;
    return path === "/" || starts(["/v/", "/c/", "/search", "/channel", "/anime", "/movie", "/guochuang", "/tv"]);
  }
  if (on("youtube.com")) {
    if (starts(["/watch", "/shorts", "/live/"])) return false;
    return path === "/" || starts(["/results", "/feed/", "/@", "/channel/", "/c/", "/user/", "/playlist"]);
  }
  if (on("douyin.com") || on("kuaishou.com") || on("tiktok.com")) return starts(["/search", "/user/", "/profile", "/@"]);
  if (on("x.com") || on("twitter.com")) {
    // 只有点开的单条推文（/用户/status/编号）算内容，时间线、搜索、通知、个人主页都是逛
    return !/^\/[^/]+\/status\/\d+/.test(path);
  }
  if (on("xiaohongshu.com")) {
    return path === "/" || path === "/explore" || path === "/explore/" || starts(["/search_result", "/user/profile"]);
  }
  return false;
}
