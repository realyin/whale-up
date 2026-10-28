// 鲸醒：记录正在看的视频 / 网页，经后台转发给本机 App（只发到 127.0.0.1）。
// 是否保存由 App 按“内容记录范围”决定，范围外的记录 App 直接丢弃。
(() => {
  // 同一个页面只运行一份（收藏时可能会被再注入一次）
  if (window.__focusGuardLoaded) return;
  window.__focusGuardLoaded = true;
  const SEND_EVERY_MS = 15000;
  const FIRST_SEND_SECONDS = 5; // 新内容尽快上报一次，好让 App 尽早判断有没有营养
  // 后台标签页的定时器会被 Chrome 限流（最慢约一分钟一次），所以按真实经过的时间计，而不是按次数
  const MAX_TICK_SECONDS = 90;
  const MIN_ACTIVE_SECONDS = 3; // 停留太短的不记
  const GENERIC_TAGS = new Set(["哔哩哔哩", "bilibili", "B站", "弹幕", "抖音", "douyin", "YouTube"]);

  const IS_SAFARI = /Safari/.test(navigator.userAgent) && !/Chrome|Chromium/.test(navigator.userAgent);
  let item = null;
  let lastSentActive = -1;
  let lastSendAt = 0;
  let lastTickAt = Date.now();

  const meta = (name) =>
    document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content?.trim() || "";
  const text = (selector) => document.querySelector(selector)?.innerText?.trim() || "";
  const clip = (s, n) => (s || "").replace(/\s+/g, " ").trim().slice(0, n);

  function onScreenArea(v) {
    // 某些情况下（窗口隐藏时）拿不到视口尺寸，就不按可见范围裁剪
    const vw = innerWidth || Infinity;
    const vh = innerHeight || Infinity;
    const r = v.getBoundingClientRect();
    const w = Math.min(r.right, vw) - Math.max(r.left, 0);
    const h = Math.min(r.bottom, vh) - Math.max(r.top, 0);
    return w > 0 && h > 0 ? w * h : 0;
  }

  const elementArea = (v) => {
    const r = v.getBoundingClientRect();
    return r.width * r.height;
  };
  const MIN_VIDEO_AREA = 40000; // 太小的（预览图、广告）不算

  /**
   * 正在播放的主视频。标签页在后台、窗口最小化或被挡住也算，滚动到评论区也算；
   * 但看不见时只算有声音的——静音自动播放的预览没人在看也没人在听。
   */
  function playingVideo() {
    const pageVisible = document.visibilityState === "visible";
    let best = null;
    let bestScore = 0;
    for (const v of document.querySelectorAll("video")) {
      if (v.paused || v.ended || v.readyState < 3) continue;
      const size = elementArea(v);
      if (size < MIN_VIDEO_AREA) continue;
      const shown = pageVisible && onScreenArea(v) > 0;
      if (v.muted && !shown) continue;
      const score = (shown ? 1e9 : 0) + size; // 屏幕上看得到的优先
      if (score > bestScore) {
        best = v;
        bestScore = score;
      }
    }
    return best;
  }

  /** 页面上最大的视频（不管在不在播），用来判断这是不是视频页、取视频时长 */
  function largestVideo() {
    let best = null;
    let bestArea = MIN_VIDEO_AREA;
    for (const v of document.querySelectorAll("video")) {
      const a = elementArea(v);
      if (a > bestArea) {
        best = v;
        bestArea = a;
      }
    }
    return best;
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

  // YouTube 是单页应用：从长视频划进 Shorts 时，上一个视频的标题、简介还藏在页面里，按页面元素取容易取成上一个。
  // 改用 YouTube 自己的 oEmbed 接口按视频编号要标题和作者（同一个网站，不用登录），取到以前先用页面标题
  const ytInfo = new Map(); // 视频编号 → { title, author }；null 表示正在要
  function youtubeId() {
    if (!location.hostname.endsWith("youtube.com")) return null;
    const p = location.pathname;
    if (p.startsWith("/shorts/")) return p.split("/")[2] || null;
    if (p === "/watch") return new URLSearchParams(location.search).get("v");
    return null;
  }
  function fetchYoutube(id) {
    if (!id || ytInfo.has(id)) return;
    ytInfo.set(id, null);
    fetch(`/oembed?format=json&url=${encodeURIComponent("https://www.youtube.com/watch?v=" + id)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (j) ytInfo.set(id, { title: j.title || "", author: j.author_name || "" }); else ytInfo.delete(id); })
      .catch(() => ytInfo.delete(id));
  }

  function extract(video) {
    const host = location.hostname;
    // 单页应用里 og:title、og:description 这些 meta 不跟着换，别拿来凑
    const spa = host.endsWith("youtube.com");
    const d = { title: "", author: "", tags: [], description: "" };

    if (host.endsWith("bilibili.com")) {
      d.title = text("h1.video-title") || text("h1");
      d.author = text(".up-name");
      d.tags = [...document.querySelectorAll(".tag-link")].map((a) => a.innerText);
      d.description = text(".desc-info-text");
    } else if (host.endsWith("douyin.com")) {
      if (video) {
        d.title = nearText(video, ['[data-e2e="video-desc"]']);
        d.author = nearText(video, ['[data-e2e="feed-video-nickname"]', '[data-e2e="video-author-title"]']);
      }
      // 去掉“展开 / 收起”按钮的文字和作者名前的 @
      d.title = d.title.replace(/\s*(展开|收起)\s*$/, "");
      d.author = d.author.replace(/^@/, "");
      d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
    } else if (host === "x.com" || host.endsWith(".x.com") || host.endsWith("twitter.com")) {
      // 先认视频旁边的那条推文：全屏看视频时可以一直往下划，网址停在第一条，视频和文字早换了
      const near = video && tweetBox(video);
      const tweet = near?.box || document.querySelector('article[data-testid="tweet"]') || document.querySelector("article");
      const pick = (sel) => near?.onScreen ? shownText(sel, near.box) : (tweet?.querySelector(sel)?.innerText?.trim() || "");
      d.title = pick('[data-testid="tweetText"]');
      d.author = pick('[data-testid="User-Name"]').split("\n").slice(0, 2).join(" ");
      d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
    } else if (host.endsWith("youtube.com")) {
      const id = youtubeId();
      fetchYoutube(id);
      const info = id && ytInfo.get(id);
      if (info) {
        d.title = info.title;
        d.author = info.author;
      } else if (location.pathname === "/watch") {
        // 只在长视频页读长视频的标题区（别的页面里它是藏着的旧内容）
        d.title = text("h1.ytd-watch-metadata");
        d.author = text("#owner #channel-name a");
      }
      d.title ||= document.title.replace(/^\(\d+\)\s*/, "");
      d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
    }

    d.title ||= meta("og:title") || document.title;
    if (!spa) {
      d.author ||= meta("author");
      if (!d.tags.length) d.tags = meta("keywords").split(/[,，]/);
      d.description ||= meta("og:description") || meta("description");
    }

    d.title = clip(d.title.replace(/_哔哩哔哩_bilibili$/, "").replace(/ - YouTube$/, ""), 200);
    d.tags = [...new Set(d.tags.map((t) => clip(t, 30)))]
      .filter((t) => t && t !== d.title && !GENERIC_TAGS.has(t))
      .slice(0, 12);
    d.description = clip(d.description, 500);
    d.author = clip(d.author, 80);
    return d;
  }

  /** 什么时候算“换了一个内容”：网址变了；抖音信息流网址不变，按视频描述 / 片源区分 */
  let lastMark = null;

  /** 推特视频的“指纹”：封面图里带着这个视频自己的编号，划到下一条时会变（网址不一定变） */
  function videoMark(video) {
    if (!video) return "";
    const poster = video.poster || video.getAttribute("poster") || "";
    const id = poster.match(/video_thumb\/(\d+)/);
    if (id) return id[1];
    if (poster) return poster.split("?")[0];
    return (video.currentSrc || video.src || "").split("?")[0];
  }

  /** 这个元素在屏幕上、没被别的东西盖住 */
  function isOnTop(el) {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1 || r.bottom <= 0 || r.top >= innerHeight) return false;
    const x = Math.min(innerWidth - 1, Math.max(0, r.left + Math.min(20, r.width / 2)));
    const y = Math.min(innerHeight - 1, Math.max(0, r.top + Math.min(10, r.height / 2)));
    const hit = document.elementFromPoint(x, y);
    return !!hit && (hit === el || el.contains(hit));
  }

  function shownText(selector, root = document) {
    for (const el of root.querySelectorAll(selector)) {
      const t = (el.innerText || "").trim();
      if (t && isOnTop(el)) return t;
    }
    return "";
  }

  /** 视频所在的那条推文：在 article 里就是它；全屏看视频时往外层找离视频最近、文字真露在屏幕上的那一层 */
  function tweetBox(video) {
    const article = video?.closest("article");
    if (article) return { box: article, onScreen: false };
    let el = video;
    for (let i = 0; el && i < 12; i++, el = el.parentElement) {
      if ([...el.querySelectorAll('[data-testid="tweetText"]')].some(isOnTop)) return { box: el, onScreen: true };
    }
    return null;
  }

  function identity(video) {
    const url = location.href.split("#")[0];
    // 推特全屏视频往下划时网址不变：加上视频自己的指纹。暂停时找不到在播的视频，沿用这个网址上一次的指纹，别一暂停就算换了一条
    if (/(^|\.)(x|twitter)\.com$/.test(location.hostname)) {
      if (video) lastMark = { url, mark: videoMark(video) };
      return lastMark?.url === url ? url + "|" + lastMark.mark : url;
    }
    if (location.hostname.endsWith("douyin.com") && video) {
      const desc = nearText(video, ['[data-e2e="video-desc"]']);
      return url + "|" + (desc || (video.currentSrc || "").split("?")[0]);
    }
    return url;
  }

  function newItem(key, video) {
    return {
      key,
      viewId: crypto.randomUUID(),
      url: location.href.split("#")[0],
      startedAt: Date.now() / 1000,
      endedAt: Date.now() / 1000,
      activeSeconds: 0,
      watchedSeconds: 0,
      backgroundSeconds: 0,
      video,
      lastVideo: null,
      lastTime: null,
    };
  }

  /** leaving：已经换到下一个内容了，页面上是新内容，这条用上次取到的标题，别取成新的 */
  function send(leaving = false) {
    if (!item || item.activeSeconds < MIN_ACTIVE_SECONDS || item.activeSeconds === lastSentActive) return;
    lastSentActive = item.activeSeconds;
    lastSendAt = Date.now();
    const video = item.video?.isConnected ? item.video : largestVideo();
    const round = (x) => Math.round(x * 10) / 10;
    const duration = video?.duration;
    if (!leaving || !item.info) item.info = extract(video);
    const payload = {
      viewId: item.viewId,
      url: item.url,
      ...item.info,
      kind: video ? "video" : "page",
      browser: IS_SAFARI ? "safari" : "chrome",
      startedAt: item.startedAt,
      endedAt: item.endedAt,
      activeSeconds: round(item.activeSeconds),
      watchedSeconds: round(item.watchedSeconds),
      backgroundSeconds: round(item.backgroundSeconds),
      mediaDuration: Number.isFinite(duration) ? duration : null,
    };
    try {
      chrome.runtime.sendMessage({ type: "views", views: [payload] }, () => void chrome.runtime.lastError);
    } catch {
      // 扩展被重新加载后，旧页面里的脚本会失效，忽略
    }
  }

  function tick() {
    const now = Date.now();
    const dt = Math.min((now - lastTickAt) / 1000, MAX_TICK_SECONDS);
    lastTickAt = now;

    const playing = playingVideo();
    const key = identity(playing);
    if (!item || item.key !== key) {
      send(true);
      fetchYoutube(youtubeId()); // 尽早去要，第一次上报（5 秒）时多半已经回来了
      item = newItem(key, playing || largestVideo());
      lastSentActive = -1;
      lastSendAt = now;
    }
    // 每 2 秒记一下这条的标题等：换到下一条时页面已经是新内容了，最后一次上报用这里记的
    if (!item.infoAt || now - item.infoAt > 2000) {
      item.info = extract(playing || item.video);
      item.infoAt = now;
    }

    // 视频按播放进度计时：后台被限流时也准确；拖动进度条不会多算
    let watched = 0;
    if (playing) {
      item.video = playing;
      const t = playing.currentTime;
      if (item.lastVideo === playing && item.lastTime !== null) {
        watched = Math.max(0, Math.min(dt, (t - item.lastTime) / (playing.playbackRate || 1)));
      }
      item.lastVideo = playing;
      item.lastTime = t;
    } else {
      item.lastVideo = null;
      item.lastTime = null;
    }

    const visible = document.visibilityState === "visible";
    if (watched > 0) {
      item.watchedSeconds += watched;
      item.activeSeconds += watched;
      if (!visible) item.backgroundSeconds += watched;
    } else if (visible && document.hasFocus()) {
      item.activeSeconds += dt; // 在看文章、图文
    }
    item.endedAt = now / 1000;

    if (lastSentActive < 0 ? item.activeSeconds >= FIRST_SEND_SECONDS : now - lastSendAt >= SEND_EVERY_MS) send();
  }

  // ---- 收藏：提取这一页的字幕 / 正文 ----

  const MAX_TEXT = 20000;

  /** B 站字幕（需要登录；拿不到返回 null） */
  async function bilibiliSubtitle() {
    const bvid = location.pathname.match(/BV\w+/)?.[0];
    if (!bvid) return null;
    try {
      const view = await fetch(`https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`, { credentials: "include" }).then((r) => r.json());
      const cid = view?.data?.cid;
      if (!cid) return null;
      const player = await fetch(`https://api.bilibili.com/x/player/wbi/v2?bvid=${bvid}&cid=${cid}`, { credentials: "include" }).then((r) => r.json());
      const subs = player?.data?.subtitle?.subtitles || [];
      const sub = subs.find((s) => /zh/.test(s.lan)) || subs[0];
      if (!sub?.subtitle_url) return null;
      const url = sub.subtitle_url.startsWith("//") ? "https:" + sub.subtitle_url : sub.subtitle_url;
      const body = await fetch(url).then((r) => r.json());
      return (body?.body || []).map((x) => x.content).join(" ");
    } catch {
      return null;
    }
  }

  /** 网页正文：在常见的正文容器里找段落文字最多的那个 */
  function mainText() {
    const selectors = "article, main, [role=main], .article, .post, .content, #content, .entry-content, .Post-RichText, .article-content";
    let best = null;
    let bestLen = 0;
    const consider = (el) => {
      const len = [...el.querySelectorAll("p")].reduce((n, p) => n + p.innerText.length, 0);
      if (len > bestLen) {
        best = el;
        bestLen = len;
      }
    };
    document.querySelectorAll(selectors).forEach(consider);
    if (bestLen < 200) {
      const parents = new Set([...document.querySelectorAll("p")].map((p) => p.parentElement));
      parents.forEach(consider);
    }
    return bestLen < 200 ? "" : best.innerText.replace(/\n{3,}/g, "\n\n").trim();
  }

  async function extractForFavorite() {
    const video = playingVideo() || largestVideo();
    const meta = extract(playingVideo() || video);
    const base = { url: location.href.split("#")[0], title: meta.title, author: meta.author };
    const descText = [meta.description, meta.tags.length ? "标签：" + meta.tags.join("、") : ""].filter(Boolean).join("\n");

    if (location.hostname.endsWith("bilibili.com")) {
      const sub = await bilibiliSubtitle();
      if (sub && sub.length > 50) return { ...base, text: sub.slice(0, MAX_TEXT), textKind: "subtitle" };
    }
    // 只有视频网站按视频处理（用简介）；其他网站即使有背景视频，也先读正文
    const videoSite = /(^|\.)(bilibili|youtube|douyin|kuaishou|tiktok|ixigua|youku|iqiyi|v\.qq)\.com$/.test(location.hostname);
    if (!videoSite || !video) {
      const text = mainText();
      if (text) return { ...base, text: text.slice(0, MAX_TEXT), textKind: "article" };
    }
    return { ...base, text: descText.slice(0, MAX_TEXT), textKind: descText ? "description" : "none" };
  }

  chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
    if (msg?.type !== "extract") return;
    extractForFavorite().then(reply);
    return true; // 异步回复
  });

  setInterval(tick, 1000);
  addEventListener("pagehide", send);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") send();
  });
})();
