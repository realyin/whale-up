// 在短视频网站上：右下角趴着大肥鱼的小脑袋，显示今天刷了几分钟；快到时限提醒；到了就盖上锁屏卡片、把视频停掉
(async () => {
  let state = await loadState();
  if (!isWatchedSite(state, location.hostname)) return;

  const img = (name) => api.runtime.getURL(`images/${name}.png`);
  const host = document.createElement("div");
  host.style.cssText = "all: initial; position: fixed; z-index: 2147483647; inset: 0; pointer-events: none;";
  const root = host.attachShadow({ mode: "closed" });
  root.innerHTML = `
    <style>
      :host { --ink: #1f2b5e; --paper: #fffdf9; --accent: #3d6fd6; }
      * { box-sizing: border-box; font-family: -apple-system, "PingFang SC", sans-serif; }
      .buddy { position: fixed; right: 12px; bottom: 90px; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: auto; }
      .head { width: 64px; height: 64px; border-radius: 50%; border: 3px solid var(--ink); background: var(--paper) center/cover;
              box-shadow: 0 3px 0 var(--ink); position: relative; }
      .count { position: absolute; left: 50%; bottom: -10px; transform: translateX(-50%); background: var(--ink); color: var(--paper);
               font-size: 11px; font-weight: 800; padding: 1px 7px 2px; border-radius: 8px; white-space: nowrap; }
      .bubble { max-width: 230px; background: var(--paper); color: var(--ink); border: 2.5px solid var(--ink); border-radius: 16px;
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
    </style>
    <div class="buddy">
      <div class="bubble" hidden></div>
      <div class="head"><span class="count"></span></div>
    </div>
    <div class="lock" hidden>
      <div class="card">
        <img src="${img("pose-sleep_curl")}">
        <h2></h2>
        <p>大肥鱼已经把视频关掉了，明天凌晨 <b class="start"></b> 点再见～<br>真想多看，点地址栏里的鲸醒图标，自己加时间。</p>
        <button>好吧，去做点别的</button>
      </div>
    </div>`;
  document.documentElement.appendChild(host);

  const $ = (sel) => root.querySelector(sel);
  const bubble = $(".bubble");
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
  $(".lock button").onclick = () => location.replace(api.runtime.getURL("rest.html"));

  function render(s) {
    const left = limitSeconds(s) - s.used;
    $(".count").textContent = `${Math.floor(s.used / 60)}/${todayLimit(s)}′`;
    if (left <= 0) return lock(s);
    if (!$(".lock").hidden) unlock();
    if (left <= 300 && !warned) {
      warned = true;
      say(`还剩 ${Math.max(1, Math.ceil(left / 60))} 分钟哦，看完这个就停吧～`, "head-angry", 8);
    }
  }

  $(".head").style.backgroundImage = `url(${img("head-watching")})`;
  render(state);
  if (limitSeconds(state) - state.used > 300) {
    say(`我盯着你呢。今天还能刷 ${Math.ceil((limitSeconds(state) - state.used) / 60)} 分钟。`, "head-watching", 4);
  }
  $(".head").onclick = () => say(`今天在这些网站上刷了 ${Math.floor(state.used / 60)} 分钟啦。`, "head-shy", 4);

  // 每 5 秒记一次：页面在前台才算
  setInterval(async () => {
    if (document.visibilityState !== "visible") return;
    state = await loadState();
    if (state.used < limitSeconds(state)) {
      state.used += 5;
      await saveState(state);
    }
    render(state);
  }, 5000);

  // 在弹出面板里加了时间、改了时长：马上生效
  api.storage.onChanged.addListener(async () => {
    state = await loadState();
    warned = limitSeconds(state) - state.used <= 300 && warned;
    render(state);
  });
})();
