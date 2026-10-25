// 在短视频网站上：右下角趴着大肥鱼的小脑袋，显示今天刷了几分钟；快到时限提醒；到了就盖上锁屏卡片、把视频停掉
(async () => {
  let state = await loadMirror();
  if (!isWatchedSite(state, location.hostname)) return;

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
  const isGood = () => !!verdict && typeof verdict === "object" && !verdict.off && verdict.isJunk === false;
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
    $(".lock .start").textContent = s.dayStartHour;
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
    // 有营养的内容不计时，也不锁
    if (isGood()) { if (!$(".lock").hidden) unlock(); return; }
    // 首页、搜索这类“逛”的页面不锁：得能去找有营养的视频
    if (left <= 0 && isBrowsePage()) {
      if (!$(".lock").hidden) unlock();
      if (!toldBrowse) { toldBrowse = true; say("今天的时间用完啦，只能看有营养的哦～", "head-angry", 6); }
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
  if (limitSeconds(state) - usedOf(state) > 300) {
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
    const video = largestVideo();
    const key = site + "|" + identity(video);
    if (key === contentKey) return;
    contentKey = key;
    const info = extract(video);
    verdict = "pending";
    render(state);
    judgeContent(key, { site, title: info.title, author: info.author, tags: info.tags.join("、"), description: info.description })
      .then((v) => {
        if (key !== contentKey) return;
        verdict = v;  // null：判断不了，按没营养算
        render(state);
        if (isGood()) say(`这个是${verdict.category || "有营养的"}，不算时间，好好看～`, "head-shy", 4);
      });
  }

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
      if ($(".lock").hidden) state = await addLocal(site, 5, isGood());
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
