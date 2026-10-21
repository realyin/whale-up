// 桌宠：渲染 Live2D 角色 Mao，提供表情、对话气泡、说话口型和施法特效。
// Swift 通过 window.mascot.* 调用；网页通过 webkit.messageHandlers.mascot 回传事件。
(() => {
  const post = (msg) => window.webkit?.messageHandlers?.mascot?.postMessage(msg);
  const stage = document.getElementById("stage");
  const app = new PIXI.Application({ view: stage, backgroundAlpha: 0, resizeTo: window, antialias: true, autoDensity: true,
                                     resolution: window.devicePixelRatio || 2 });
  let model = null;
  let speaking = false;
  const effects = new PIXI.Container();

  // 表情名（模型里只有编号，按实际效果对应）
  const MOODS = { idle: null, happy: "exp_02", excited: "exp_04", watching: "exp_05", angry: "exp_08", shy: "exp_06" };

  async function load() {
    model = await PIXI.live2d.Live2DModel.from("vendor/Mao/Mao.model3.json", { autoInteract: false });
    app.stage.addChild(model);
    app.stage.addChild(effects);
    layout();
    window.addEventListener("resize", layout);
    app.ticker.add(tick);
    post({ type: "ready" });
  }

  function layout() {
    if (!model) return;
    const h = window.innerHeight * 0.80;
    const scale = h / model.internalModel.height;
    model.scale.set(scale);
    model.x = (window.innerWidth - model.width) / 2;
    model.y = window.innerHeight - model.height + model.height * 0.02;
    report();
  }

  // 说话时嘴巴一张一合
  let mouthPhase = 0;
  function tick(delta) {
    if (!model) return;
    const core = model.internalModel.coreModel;
    if (speaking) {
      mouthPhase += delta * 0.35;
      core.setParameterValueById("ParamMouthOpenY", 0.35 + 0.45 * Math.abs(Math.sin(mouthPhase)));
    }
    for (const p of [...effects.children]) {
      if (p.life !== undefined) {
        p.life -= delta;
        p.x += p.vx * delta;
        p.y += p.vy * delta;
        p.alpha = Math.max(0, p.life / p.maxLife);
        if (p.life <= 0) p.destroy();
      }
    }
  }

  // ---- 对外接口 ----

  let currentMood = "idle";
  function setMood(mood) {
    currentMood = mood;
    if (!model) return;
    const name = MOODS[mood];
    if (name) model.expression(name);
    else model.internalModel.motionManager.expressionManager?.resetExpression();
  }

  function setSpeaking(on) {
    speaking = on;
    if (!on && model) model.internalModel.coreModel.setParameterValueById("ParamMouthOpenY", 0);
  }

  /** 对话气泡。buttons: [{id, title, style, waitSeconds}]；reasons: [{id, title}] */
  function say(text, buttons = [], reasons = []) {
    const bubble = document.getElementById("bubble");
    document.getElementById("text").textContent = text;
    const box = document.getElementById("buttons");
    const reasonBox = document.getElementById("reasons");
    box.innerHTML = "";
    reasonBox.innerHTML = "";
    for (const r of reasons) {
      const el = document.createElement("button");
      el.className = "chip";
      el.textContent = r.title;
      el.onclick = () => {
        if (reasonBox.dataset.done) return;
        reasonBox.dataset.done = "1";
        el.classList.add("on");
        post({ type: "reason", id: r.id });
      };
      reasonBox.appendChild(el);
    }
    delete reasonBox.dataset.done;
    for (const b of buttons) {
      const el = document.createElement("button");
      el.className = b.style || "secondary";
      el.onclick = () => post({ type: "button", id: b.id });
      box.appendChild(el);
      let left = b.waitSeconds || 0;
      const render = () => {
        el.textContent = left > 0 ? `${b.title}（${left}）` : b.title;
        el.disabled = left > 0;
      };
      render();
      if (left > 0) {
        const t = setInterval(() => { left -= 1; render(); if (left <= 0) clearInterval(t); }, 1000);
      }
    }
    bubble.hidden = false;
    report();
  }

  function hideBubble() {
    document.getElementById("bubble").hidden = true;
    report();
  }

  /** 施法：挥魔杖 + 星星朝 (dx, dy) 方向飞出，最后炸开 */
  function cast(dx = -1, dy = -1) {
    if (!model) return;
    model.motion("TapBody", 3, PIXI.live2d.MotionPriority.FORCE);
    // 举起魔杖后，从杖头（画面左上方）朝 (dx, dy) 方向喷出星星
    const ox = window.innerWidth * 0.17;
    const oy = window.innerHeight * 0.27;
    const len = Math.hypot(dx, dy) || 1;
    let n = 0;
    setTimeout(() => {
      const timer = setInterval(() => {
        for (let i = 0; i < 5; i++) star(ox, oy, (dx / len) * (4 + Math.random() * 4) + (Math.random() - 0.5) * 2.5,
                                       (dy / len) * (4 + Math.random() * 4) + (Math.random() - 0.5) * 2.5, 45);
        if (++n > 16) clearInterval(timer);
      }, 45);
    }, 350);
  }

  /** 一团星星炸开（网页被关掉的那一下） */
  function burst(x = window.innerWidth / 2, y = window.innerHeight * 0.25) {
    for (let i = 0; i < 40; i++) {
      const a = Math.random() * Math.PI * 2;
      const v = 2 + Math.random() * 5;
      star(x, y, Math.cos(a) * v, Math.sin(a) * v, 50);
    }
  }

  const COLORS = [0xff6fa8, 0xffd84d, 0x9be7ff, 0xc9a2ff, 0xffffff];
  function star(x, y, vx, vy, life) {
    const g = new PIXI.Graphics();
    const outer = 4 + Math.random() * 6;
    const inner = outer * 0.45;
    const points = [];
    for (let i = 0; i < 10; i++) {
      const r = i % 2 ? inner : outer;
      const a = (Math.PI / 5) * i - Math.PI / 2;
      points.push(Math.cos(a) * r, Math.sin(a) * r);
    }
    g.beginFill(COLORS[Math.floor(Math.random() * COLORS.length)]);
    g.drawPolygon(points);
    g.endFill();
    g.rotation = Math.random() * Math.PI;
    Object.assign(g, { x, y, vx, vy, life, maxLife: life });
    effects.addChild(g);
  }

  // 被戳一下：害羞地动一动，过一会儿恢复
  let tapTimer = null;
  function tap() {
    if (!model) return;
    model.motion("TapBody", Math.floor(Math.random() * 3));
    model.expression(MOODS.shy);
    post({ type: "tapped" });
    clearTimeout(tapTimer);
    tapTimer = setTimeout(() => setMood(currentMood), 2500);
  }

  // ---- 鼠标：拖动窗口、点角色、告诉 Swift 哪里可以点穿 ----

  let drag = null;
  stage.addEventListener("mousedown", (e) => { drag = { x: e.screenX, y: e.screenY, moved: false }; });
  window.addEventListener("mousemove", (e) => {
    if (!drag) return;
    const dx = e.screenX - drag.x;
    const dy = e.screenY - drag.y;
    if (Math.abs(dx) + Math.abs(dy) > 2) drag.moved = true;
    if (drag.moved) post({ type: "dragBy", dx, dy });
    drag.x = e.screenX;
    drag.y = e.screenY;
  });
  window.addEventListener("mouseup", () => {
    if (drag && !drag.moved) tap();
    if (drag?.moved) post({ type: "dragEnd" });
    drag = null;
  });

  /** 可交互区域（窗口坐标，左上为原点）：角色身体 + 气泡；其余区域鼠标点穿 */
  function report() {
    const rects = [];
    if (model) {
      const b = model.getBounds();
      rects.push({ x: b.x + b.width * 0.22, y: b.y + b.height * 0.08, w: b.width * 0.56, h: b.height * 0.92 });
    }
    const bubble = document.getElementById("bubble");
    if (!bubble.hidden) {
      const r = bubble.getBoundingClientRect();
      rects.push({ x: r.x, y: r.y, w: r.width, h: r.height + 10 });
    }
    post({ type: "hitRects", rects });
  }

  /** 开发用：直接切换某个表情 */
  function expr(name) { model?.expression(name); }

  window.mascot = { setMood, setSpeaking, say, hideBubble, cast, burst, tap, report, expr };
  load().catch((e) => post({ type: "error", message: String(e) }));
})();
