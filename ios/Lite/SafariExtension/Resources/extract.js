// 从网页里取出视频的标题、作者、标签、简介（给 AI 判断用）。规则和 Mac 版 Chrome 扩展一样，
// 另外加了手机版网页（m.bilibili.com、m.youtube.com 等）的兜底：取不到就用网页标题和分享信息
const GENERIC_TAGS = new Set(["哔哩哔哩", "bilibili", "B站", "弹幕", "抖音", "douyin", "YouTube"]);
const meta = (name) =>
  document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content?.trim() || "";
const text = (selector) => document.querySelector(selector)?.innerText?.trim() || "";
const clip = (s, n) => (s || "").replace(/\s+/g, " ").trim().slice(0, n);
const MIN_VIDEO_AREA = 40000; // 太小的（预览图、广告）不算

/** 页面上最大的视频，用来区分信息流里的每一条 */
function largestVideo() {
  let best = null;
  let bestArea = MIN_VIDEO_AREA;
  for (const v of document.querySelectorAll("video")) {
    const r = v.getBoundingClientRect();
    const a = r.width * r.height;
    if (a > bestArea) { best = v; bestArea = a; }
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
  } else if (host.endsWith("youtube.com")) {
    d.title = text("ytd-reel-video-renderer[is-active] h2") || text("h1.ytd-watch-metadata") || text(".slim-video-metadata-header h2")
      || text("ytm-shorts-lockup-view-model h3");
    d.author = text("ytd-reel-video-renderer[is-active] #channel-name a") || text("#owner #channel-name a")
      || text(".slim-owner-channel-name");
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
