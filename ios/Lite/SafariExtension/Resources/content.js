// 在短视频网站上：右下角趴着大肥鱼的小脑袋，显示今天刷了几分钟；快到时限提醒；到了就盖上锁屏卡片、把视频停掉
(async () => {
  let state = await loadMirror();
  // 这边记的名单可能还是旧的（刚在鲸醒 App 里加了网站）：不在名单里时先和 App 同步一次再判断，
  // 不然新加的网站永远等不到同步、永远不生效
  if (!isWatchedSite(state, location.hostname)) {
    // 一分钟内同步过就不再同步（不在名单里的网页很多，别每个都去问 App）
    if (Date.now() - num(state.lastSync) > 60000) {
      try { state = (await sync()) || state; } catch (e) { /* 连不上就按旧名单 */ }
    }
    if (!isWatchedSite(state, location.hostname)) return;
  }

  // 图片先读进来存成 data: 地址：扩展更新后，已经打开的网页里扩展地址会失效，头像就成了空白
  const pictures = {};
  const img = (name) => pictures[name] || api.runtime.getURL(`images/${name}.png`);
  await Promise.all(["head-watching", "head-angry", "head-shy", "pose-sleep_curl"].map(async (name) => {
    try {
      const blob = await (await fetch(api.runtime.getURL(`images/${name}.png`))).blob();
      pictures[name] = await new Promise((ok) => { const r = new FileReader(); r.onload = () => ok(r.result); r.readAsDataURL(blob); });
    } catch (e) { /* 读不到就还用扩展地址 */ }
  }));
  const host = document.createElement("div");
  host.style.cssText = "all: initial; position: fixed; z-index: 2147483647; inset: 0; pointer-events: none;";
  const root = host.attachShadow({ mode: "closed" });
  root.innerHTML = `
    <style>
      :host { --ink: #1f2b5e; --paper: #fffdf9; --accent: #3d6fd6; }
      * { box-sizing: border-box; font-family: -apple-system, "PingFang SC", sans-serif; }
      .buddy { position: fixed; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: none; }
      .buddy.left { align-items: flex-start; }
      .buddy.snap { transition: left .25s cubic-bezier(.3,1.4,.5,1), bottom .25s; }
      .head { width: 64px; height: 64px; border-radius: 50%; border: 3px solid var(--ink); background: var(--paper) center/cover;
              box-shadow: 0 3px 0 var(--ink); position: relative; pointer-events: auto; touch-action: none; -webkit-user-select: none; user-select: none; }
      .head.dragging { transform: scale(1.12); box-shadow: 0 8px 16px rgba(20,30,70,.35); }
      .tag { position: absolute; left: 50%; top: -12px; transform: translateX(-50%); white-space: nowrap; font-size: 10.5px; font-weight: 800;
             padding: 1px 6px 2px; border-radius: 8px; border: 1.5px solid var(--ink); background: var(--paper); color: var(--ink); }
      .tag[hidden] { display: none; }
      .tag.good { background: #3d6fd6; color: #fff; }
      .tag.junk { background: #eb6834; color: #fff; }
      .count.free { background: #3d6fd6; }
      .count { position: absolute; left: 50%; bottom: -10px; transform: translateX(-50%); background: var(--ink); color: var(--paper);
               font-size: 11px; font-weight: 800; padding: 1px 7px 2px; border-radius: 8px; white-space: nowrap; }
      .bubble { pointer-events: auto; max-width: 230px; background: var(--paper); color: var(--ink); border: 2.5px solid var(--ink); border-radius: 16px;
                padding: 10px 12px; font-size: 14px; font-weight: 700; line-height: 1.45; box-shadow: 0 3px 0 rgba(0,0,0,.12);
                transform-origin: 100% 100%; animation: pop .3s cubic-bezier(.3,1.5,.5,1); }
      .bubble[hidden] { display: none; }
      @keyframes pop { from { transform: scale(.5); opacity: 0; } }
      .lock { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; padding: 24px;
              background: rgba(20, 26, 60, .55); backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); pointer-events: auto; }
      .lock[hidden] { display: none; }
      .card { width: 100%; max-width: 340px; background: var(--paper); border: 3px solid var(--ink); border-radius: 26px; padding: 18px 20px 22px;
              text-align: center; color: var(--ink); box-shadow: 0 6px 0 var(--ink); animation: pop .35s cubic-bezier(.3,1.5,.5,1); }
      .card img { width: 200px; }
      .card h2 { margin: 6px 0 8px; font-size: 22px; }
      .card p { margin: 0 0 16px; font-size: 14px; line-height: 1.6; color: #44507a; }
      .card button { width: 100%; border: 2.5px solid var(--ink); border-radius: 999px; background: var(--accent); color: #fff; font-size: 16px;
                     font-weight: 800; padding: 12px; box-shadow: 0 3px 0 var(--ink); }
      .card button.home { background: var(--paper); color: var(--ink); margin-bottom: 10px; }
      .card button[hidden] { display: none; }
    </style>
    <div class="buddy">
      <div class="bubble" hidden></div>
      <div class="head"><span class="tag" hidden></span><span class="count"></span></div>
    </div>
    <div class="lock" hidden>
      <div class="card">
        <img src="${img("pose-sleep_curl")}">
        <h2></h2>
        <p>这个视频大肥鱼不让看了，明天凌晨 <b class="start"></b> 点再见～<br>有营养的照样能看：回首页找找。真想多看，点地址栏里的鲸醒图标，自己加时间。</p>
        <button class="home">回首页找点有营养的</button>
        <button class="rest">好吧，去做点别的</button>
      </div>
    </div>`;
  document.documentElement.appendChild(host);

  const $ = (sel) => root.querySelector(sel);
  const bubble = $(".bubble");
  // 当前内容的 AI 判断：undefined 还没看、"pending" 判断中、{isJunk,...}、{off:true} 没开 AI、null 判断失败
  let verdict;
  const isGood = () => !isWhole() && !!verdict && typeof verdict === "object" && !verdict.off && verdict.isJunk === false;
  // 只拦视频的网站（如推特）：不计时、不锁；点开带视频的内容时让 AI 判断，没营养的就退回去
  const isVideoOnly = () => !isWhole() && (state.videoOnlySites || []).some((x) => location.hostname === x || location.hostname.endsWith("." + x));
  // 整站都算的网站（如虎扑）：不问 AI、首页也锁、锁屏卡片上不放“回首页”
  const isWhole = () => (state.wholeSites || []).some((x) => location.hostname === x || location.hostname.endsWith("." + x));
  let bubbleTimer = null;
  let warned = false;

  function say(text, face, seconds = 5) {
    $(".head").style.backgroundImage = `url(${img(face)})`;
    bubble.textContent = text;
    bubble.hidden = false;
    clearTimeout(bubbleTimer);
    bubbleTimer = setTimeout(() => { bubble.hidden = true; }, seconds * 1000);
  }

  // 锁上以后，页面上所有视频一直停着
  let pauser = null;
  function lock(s) {
    $(".lock h2").textContent = `今天的 ${todayLimit(s)} 分钟用完啦`;
    $(".lock button.home").hidden = isWhole();
    $(".lock p").innerHTML = isWhole()
      ? `这个网站今天不能再刷了，明天凌晨 <b>${s.dayStartHour}</b> 点再见～<br>真想多看，点地址栏里的鲸醒图标，自己加时间。`
      : `这个视频大肥鱼不让看了，明天凌晨 <b>${s.dayStartHour}</b> 点再见～<br>有营养的照样能看：回首页找找。真想多看，点地址栏里的鲸醒图标，自己加时间。`;
    $(".lock").hidden = false;
    $(".buddy").style.display = "none";
    if (!pauser) {
      pauser = setInterval(() => document.querySelectorAll("video, audio").forEach((v) => { v.pause(); v.muted = true; }), 400);
    }
  }
  function unlock() {
    $(".lock").hidden = true;
    $(".buddy").style.display = "";
    clearInterval(pauser);
    pauser = null;
  }
  $(".lock button.rest").onclick = () => location.replace(api.runtime.getURL("rest.html"));
  $(".lock button.home").onclick = () => location.assign(location.origin + "/");
  let toldBrowse = false;
  let pendingSince = 0;
  let toldJudging = null;

  function render(s) {
    // 万一还是算出了不是数字的东西：按用完了算，宁可锁上也不放过
    const left = Number.isFinite(limitSeconds(s) - usedOf(s)) ? limitSeconds(s) - usedOf(s) : 0;
    // 看有营养的视频时不计时：数字换成“不计时”，免得看着像卡住了
    $(".count").textContent = isGood() ? "不计时" : `${Math.floor(usedOf(s) / 60)}/${todayLimit(s)}′`;
    $(".count").classList.toggle("free", isGood());
    // 头顶的小标签：AI 判断的结果
    const tag = $(".tag");
    tag.hidden = !verdict || verdict.off;
    tag.className = "tag" + (verdict === "pending" ? "" : verdict && verdict.isJunk ? " junk" : " good");
    tag.textContent = verdict === "pending" ? "判断中…" : verdict && !verdict.off ? (verdict.isJunk ? "没营养" : "✓ 有营养") : "";
    if (tag.hidden) tag.className = "tag";
    // 有营养的内容不计时，也不锁；只拦视频的网站也不锁（没营养的视频直接退回）
    if (isGood() || isVideoOnly()) { if (!$(".lock").hidden) unlock(); if (isVideoOnly() && !isGood()) $(".count").textContent = "拦视频"; return; }
    // 首页、搜索这类“逛”的页面不锁：得能去找有营养的视频
    if (left <= 0 && isBrowsePage() && !isWhole()) {
      if (!$(".lock").hidden) unlock();
      if (!toldBrowse) { toldBrowse = true; say("今天的时间用完啦，只能看有营养的哦～", "head-angry", 6); }
      return;
    }
    // 额度用完以后新点开的内容：AI 还在判断就先不锁（最多等 30 秒），免得有营养的视频先被锁一下、停掉
    if (left <= 0 && verdict === "pending" && Date.now() - pendingSince < 30000) {
      if (!$(".lock").hidden) unlock();
      if (toldJudging !== contentKey) { toldJudging = contentKey; say("时间用完了，我先看看这个有没有营养…", "head-watching", 4); }
      return;
    }
    if (left <= 0) return lock(s);
    if (!$(".lock").hidden) unlock();
    if (left <= 300 && !warned) {
      warned = true;
      say(`还剩 ${Math.max(1, Math.ceil(left / 60))} 分钟哦，看完这个就停吧～`, "head-angry", 8);
    }
  }

  $(".head").style.backgroundImage = `url(${img("head-watching")})`;
  render(state);
  if (isVideoOnly()) {
    say("这里我不计时，只盯着你点开的视频～", "head-watching", 4);
  } else if (limitSeconds(state) - usedOf(state) > 300) {
    say(`我盯着你呢。今天还能刷 ${Math.ceil((limitSeconds(state) - usedOf(state)) / 60)} 分钟。`, "head-watching", 4);
  }
  // ---- 拖动她：按住滑到别处，松手贴到最近的左边或右边；位置记住，换网页也一样 ----
  const buddy = $(".buddy");
  const head = $(".head");
  const SIZE = 64, MARGIN = 10;
  let pos = { side: "right", y: 0.62 };
  try { pos = (await api.storage.local.get("whaleupPos")).whaleupPos || pos; } catch (e) { /* 读不到就放默认位置 */ }

  // 按脑袋的中心定位、从底边算：上面冒出气泡时，脑袋不会被往下挤
  function place(animate) {
    const centerY = Math.min(window.innerHeight - SIZE / 2 - MARGIN, Math.max(SIZE / 2 + MARGIN, pos.y * window.innerHeight));
    buddy.classList.toggle("snap", !!animate);
    buddy.classList.toggle("left", pos.side === "left");
    buddy.style.top = "auto";
    buddy.style.bottom = `${window.innerHeight - centerY - SIZE / 2}px`;
    if (pos.side === "left") { buddy.style.left = `${MARGIN}px`; buddy.style.right = "auto"; }
    else { buddy.style.right = `${MARGIN}px`; buddy.style.left = "auto"; }
  }
  place(false);
  window.addEventListener("resize", () => place(false));

  let drag = null;
  head.addEventListener("pointerdown", (e) => {
    drag = { x: e.clientX, y: e.clientY, moved: false };
    head.setPointerCapture(e.pointerId);
  });
  head.addEventListener("pointermove", (e) => {
    if (!drag) return;
    if (!drag.moved && Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 6) return;
    drag.moved = true;
    head.classList.add("dragging");
    bubble.hidden = true;
    // 拖的时候脑袋跟着手指走
    buddy.classList.remove("snap", "left");
    buddy.style.right = "auto";
    buddy.style.left = `${e.clientX - buddy.offsetWidth + SIZE / 2}px`;
    buddy.style.bottom = `${window.innerHeight - e.clientY - SIZE / 2}px`;
  });
  const drop = (e) => {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    head.classList.remove("dragging");
    if (!moved) {
      if (isVideoOnly()) { say(videoNote, "head-watching", 6); return; }
      const goodMin = Math.floor(Object.values(state.good || {}).reduce((a, b) => a + num(b), 0) / 60);
      say(`没营养的今天刷了 ${Math.floor(usedOf(state) / 60)} 分钟（上限 ${todayLimit(state)} 分钟，App 和网页一起算）`
        + (goodMin > 0 ? `；有营养的看了 ${goodMin} 分钟，不算时间～` : "。"), "head-shy", 5);
      return;
    }
    pos = { side: e.clientX < window.innerWidth / 2 ? "left" : "right", y: e.clientY / window.innerHeight };
    place(true);
    api.storage.local.set({ whaleupPos: pos }).catch(() => {});
  };
  head.addEventListener("pointerup", drop);
  head.addEventListener("pointercancel", drop);

  // ---- AI 判断：换了一个视频 / 网页就问一次（判断过的直接用），有营养的不计时 ----
  const site = state.sites.find((x) => location.hostname === x || location.hostname.endsWith("." + x)) || location.hostname;
  let contentKey = null;
  function checkContent() {
    if (isWhole()) { verdict = undefined; return; }
    if (isVideoOnly()) return checkVideo();
    const video = largestVideo();
    const key = site + "|" + identity(video);
    if (key === contentKey) return;
    contentKey = key;
    const info = extract(video);
    verdict = "pending";
    pendingSince = Date.now();
    render(state);
    judgeContent(key, { site, title: info.title, author: info.author, tags: info.tags.join("、"), description: info.description, tweet: info.tweet || "" })
      .then((v) => {
        if (key !== contentKey) return;
        verdict = v && v.noText ? null : v;  // null：判断不了（推文没字、没网等），按没营养算
        render(state);
        if (isGood()) say(`这个是${verdict.category || "有营养的"}，不算时间，好好看～`, "head-shy", 4);
      });
  }

  // ---- 只拦视频：点开一条带视频的内容（推特的 /status/ 页）时问 AI，没营养的暂停、3 秒后退回 ----
  let videoKey = null;
  let backTimer = null;
  let waited = { key: null, n: 0 };
  // 这条视频为什么拦 / 没拦：点她的脑袋能看到，放过的时候也直接说出来，不然看不出来是没生效还是判断成有营养
  let videoNote = "还没点开带视频的推文～";
  function note(text, face = "head-watching", seconds = 5) { videoNote = text; say(text, face, seconds); }
  function checkVideo() {
    const video = largestVideo();
    if (isBrowsePage() || !video) {
      // 回到时间线 / 没有视频：不管
      if (videoKey) { videoKey = null; verdict = undefined; clearTimeout(backTimer); render(state); }
      videoNote = isBrowsePage() ? "现在在时间线上：时间线里不拦，点开一条带视频的推文我再看～" : "这一页我没找到视频～";
      return;
    }
    const key = site + "|" + identity(video);
    if (key === videoKey) return;
    const info = extract(video);
    // 推特的推文文字常比视频晚出来一会儿：没读到字先等两秒（每秒看一次），还没有再交给 App 去推特接口要
    if (!info.title) {
      if (waited.key !== key) waited = { key, n: 0 };
      if (++waited.n < 3) return;
    }
    videoKey = key;
    clearTimeout(backTimer);
    verdict = "pending";
    render(state);
    judgeContent(key, { site, title: info.title, author: info.author, tags: info.tags.join("、"), description: info.description, tweet: info.tweet || "" })
      .then((v) => {
        if (key !== videoKey) return;
        // 推文只有视频、一个字都没有：AI 没东西可判断，宁可放过，别误伤要看的内容
        if (v && v.noText) { verdict = undefined; render(state); note("这条推文一个字都没有，我看不出好坏，先放过～"); return; }
        verdict = v;
        render(state);
        if (isGood()) { note(`这个视频是${verdict.category || "有营养的"}（${verdict.reason || "有收获"}），看吧～`, "head-shy", 4); return; }
        // 判断不了（没开 AI、没网）就不拦：只拦视频的网站宁可放过，也别误伤要看的内容
        if (!v || v.off || v.isJunk !== true) {
          verdict = undefined; render(state);
          note(v && v.off ? "AI 判断还没打开，我分不出好坏，先放过。去鲸醒 App 里打开“AI 判断”、填上 Key 就能拦～"
            : "AI 没回我（可能没网），这条先放过～", "head-angry", 7);
          return;
        }
        document.querySelectorAll("video").forEach((x) => x.pause());
        note(`这个视频没什么营养（${v.reason || v.category || "消遣"}），3 秒后帮你退回去～`, "head-angry", 4);
        backTimer = setTimeout(() => {
          if (key !== videoKey) return;
          if (history.length > 1) history.back();
          else location.assign(location.origin + "/home");
        }, 3000);
      });
  }
  // 只拦视频的网站切页面不刷新网页（单页应用），每秒看一眼，点开视频能马上判断
  setInterval(() => {
    if (document.visibilityState === "visible" && isVideoOnly()) { try { checkVideo(); } catch (e) { /* 不影响别的 */ } }
  }, 1000);

  // 每 5 秒：页面在前台、还没锁上，就先在本地记 5 秒、马上判断；再顺带和 App 同步（同步卡住也不影响计时）
  async function refresh(synced) {
    if (!synced) return;
    if (limitSeconds(synced) - usedOf(synced) > 300) warned = false;
    state = synced;
    render(state);
  }
  // 扩展的存储读写失败（常见于扩展更新后、这个网页还是更新前打开的）：照样在这个网页里记账、到点照锁，
  // 并提示刷新一下。计时绝不能因为出错就停
  let broken = false;
  function addInMemory(seconds) {
    const book = isGood() ? (state.good ||= {}) : (state.web ||= {});
    book[site] = num(book[site]) + seconds;
  }
  setInterval(async () => {
    if (document.visibilityState !== "visible") return;
    try { checkContent(); } catch (e) { /* 取不到视频信息不影响计时 */ }
    try {
      // 只拦视频的网站不计时
      if (isVideoOnly()) state = await loadMirror();
      else if ($(".lock").hidden) state = await addLocal(site, 5, isGood());
      else state = await loadMirror();
      broken = false;
    } catch (e) {
      if ($(".lock").hidden) addInMemory(5);
      if (!broken) { broken = true; say("鲸醒刚更新过，刷新一下页面就好～（先按这个网页里记的算）", "head-angry", 8); }
    }
    render(state);
    if (!broken) sync().then(refresh).catch(() => {});
  }, 5000);
  sync().then(refresh).catch(() => {});
  try { checkContent(); } catch (e) { /* 同上 */ }

  // 切回这个页面时马上同步一次（可能在 App 或弹出面板里改了设置）
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && !broken) sync().then(refresh).catch(() => {});
  });
})();
