// 专注守护：记录正在看的视频 / 网页，经后台转发给本机 App（只发到 127.0.0.1）。
// 是否保存由 App 按“内容记录范围”决定，范围外的记录 App 直接丢弃。
(() => {
  const SEND_EVERY_SECONDS = 15;
  const MIN_ACTIVE_SECONDS = 3; // 停留太短的不记
  const GENERIC_TAGS = new Set(["哔哩哔哩", "bilibili", "B站", "弹幕", "抖音", "douyin", "YouTube"]);

  let item = null;
  let lastSentActive = -1;

  const meta = (name) =>
    document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content?.trim() || "";
  const text = (selector) => document.querySelector(selector)?.innerText?.trim() || "";
  const clip = (s, n) => (s || "").replace(/\s+/g, " ").trim().slice(0, n);

  /** 画面里露出面积最大的视频；playingOnly 时只看正在播放的 */
  function mainVideo(playingOnly) {
    let best = null;
    let bestArea = 40000; // 太小的（预览图、广告）不算
    // 某些情况下（窗口隐藏时）拿不到视口尺寸，就不按可见范围裁剪
    const vw = innerWidth || Infinity;
    const vh = innerHeight || Infinity;
    for (const v of document.querySelectorAll("video")) {
      if (playingOnly && v.paused) continue;
      const r = v.getBoundingClientRect();
      const w = Math.min(r.right, vw) - Math.max(r.left, 0);
      const h = Math.min(r.bottom, vh) - Math.max(r.top, 0);
      if (w > 0 && h > 0 && w * h > bestArea) {
        best = v;
        bestArea = w * h;
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

  function extract(video) {
    const host = location.hostname;
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
      d.tags = (d.title.match(/#[^\s#]+/g) || []).map((t) => t.slice(1));
    } else if (host.endsWith("youtube.com")) {
      d.title = text("ytd-reel-video-renderer[is-active] h2") || text("h1.ytd-watch-metadata");
      d.author = text("ytd-reel-video-renderer[is-active] #channel-name a") || text("#owner #channel-name a");
    }

    d.title ||= meta("og:title") || document.title;
    d.author ||= meta("author");
    if (!d.tags.length) d.tags = meta("keywords").split(/[,，]/);
    d.description ||= meta("og:description") || meta("description");

    d.title = clip(d.title.replace(/_哔哩哔哩_bilibili$/, "").replace(/ - YouTube$/, ""), 200);
    d.tags = [...new Set(d.tags.map((t) => clip(t, 30)))]
      .filter((t) => t && t !== d.title && !GENERIC_TAGS.has(t))
      .slice(0, 12);
    d.description = clip(d.description, 500);
    d.author = clip(d.author, 80);
    return d;
  }

  /** 什么时候算“换了一个内容”：网址变了；抖音信息流网址不变，按视频描述 / 片源区分 */
  function identity(video) {
    const url = location.href.split("#")[0];
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
      video,
    };
  }

  function send() {
    if (!item || item.activeSeconds < MIN_ACTIVE_SECONDS || item.activeSeconds === lastSentActive) return;
    lastSentActive = item.activeSeconds;
    const video = item.video?.isConnected ? item.video : mainVideo(false);
    const duration = video?.duration;
    const payload = {
      viewId: item.viewId,
      url: item.url,
      ...extract(video),
      kind: video ? "video" : "page",
      browser: "chrome",
      startedAt: item.startedAt,
      endedAt: item.endedAt,
      activeSeconds: item.activeSeconds,
      watchedSeconds: item.watchedSeconds,
      mediaDuration: Number.isFinite(duration) ? duration : null,
    };
    try {
      chrome.runtime.sendMessage({ type: "views", views: [payload] }, () => void chrome.runtime.lastError);
    } catch {
      // 扩展被重新加载后，旧页面里的脚本会失效，忽略
    }
  }

  function tick() {
    const playing = mainVideo(true);
    const key = identity(playing);
    if (!item || item.key !== key) {
      send();
      item = newItem(key, playing || mainVideo(false));
      lastSentActive = -1;
    }
    if (playing) item.video = playing;

    const visible = document.visibilityState === "visible";
    if (visible && (document.hasFocus() || playing)) item.activeSeconds += 1;
    if (visible && playing) item.watchedSeconds += 1;
    item.endedAt = Date.now() / 1000;

    if (item.activeSeconds > 0 && item.activeSeconds % SEND_EVERY_SECONDS === 0) send();
  }

  setInterval(tick, 1000);
  addEventListener("pagehide", send);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") send();
  });
})();
