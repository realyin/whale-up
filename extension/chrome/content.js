// 专注守护：记录正在看的视频 / 网页，经后台转发给本机 App（只发到 127.0.0.1）。
// 是否保存由 App 按“内容记录范围”决定，范围外的记录 App 直接丢弃。
(() => {
  const SEND_EVERY_MS = 15000;
  const FIRST_SEND_SECONDS = 5; // 新内容尽快上报一次，好让 App 尽早判断有没有营养
  // 后台标签页的定时器会被 Chrome 限流（最慢约一分钟一次），所以按真实经过的时间计，而不是按次数
  const MAX_TICK_SECONDS = 90;
  const MIN_ACTIVE_SECONDS = 3; // 停留太短的不记
  const GENERIC_TAGS = new Set(["哔哩哔哩", "bilibili", "B站", "弹幕", "抖音", "douyin", "YouTube"]);

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
      backgroundSeconds: 0,
      video,
      lastVideo: null,
      lastTime: null,
    };
  }

  function send() {
    if (!item || item.activeSeconds < MIN_ACTIVE_SECONDS || item.activeSeconds === lastSentActive) return;
    lastSentActive = item.activeSeconds;
    lastSendAt = Date.now();
    const video = item.video?.isConnected ? item.video : largestVideo();
    const round = (x) => Math.round(x * 10) / 10;
    const duration = video?.duration;
    const payload = {
      viewId: item.viewId,
      url: item.url,
      ...extract(video),
      kind: video ? "video" : "page",
      browser: "chrome",
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
      send();
      item = newItem(key, playing || largestVideo());
      lastSentActive = -1;
      lastSendAt = now;
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

  setInterval(tick, 1000);
  addEventListener("pagehide", send);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") send();
  });
})();
