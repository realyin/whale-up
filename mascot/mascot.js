// 桌宠：渲染角色（Live2D 模型或透明图片），提供表情、对话气泡、说话口型和施法特效。
// 角色包在 characters/<id>/character.json；Swift 通过 window.mascot.* 调用，网页通过 webkit.messageHandlers.mascot 回传事件。
(() => {
  const post = (msg) => window.webkit?.messageHandlers?.mascot?.postMessage(msg);
  const stage = document.getElementById("stage");
  const app = new PIXI.Application({ view: stage, backgroundAlpha: 0, resizeTo: window, antialias: true, autoDensity: true,
                                     resolution: window.devicePixelRatio || 2 });
  const effects = new PIXI.Container();
  const characterId = new URLSearchParams(location.search).get("character") || "mao";
  let actor = null; // 当前角色驱动（Live2D 或图片）
  let currentMood = "idle";

  /** file:// 下用 XHR 读 JSON（fetch 不支持本地文件） */
  function loadJSON(url) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open("GET", url);
      xhr.onload = () => { try { resolve(JSON.parse(xhr.responseText)); } catch (e) { reject(e); } };
      xhr.onerror = () => reject(new Error("读不到 " + url));
      xhr.send();
    });
  }

  // ---- Live2D 角色 ----

  async function live2dActor(base, spec) {
    const model = await PIXI.live2d.Live2DModel.from(base + spec.model, { autoInteract: false });
    app.stage.addChild(model);
    const moods = spec.expressions || {};
    let speaking = false;
    let phase = 0;
    return {
      bounds: () => model.getBounds(),
      layout() {
        model.scale.set(spec.height / model.internalModel.height);
        model.x = (window.innerWidth - model.width) / 2;
        model.y = window.innerHeight - model.height + model.height * 0.02;
      },
      tick(delta) {
        if (!speaking) return;
        phase += delta * 0.35;
        model.internalModel.coreModel.setParameterValueById("ParamMouthOpenY", 0.35 + 0.45 * Math.abs(Math.sin(phase)));
      },
      setMood(mood) {
        if (moods[mood]) model.expression(moods[mood]);
        else model.internalModel.motionManager.expressionManager?.resetExpression();
      },
      setSpeaking(on) {
        speaking = on;
        if (!on) model.internalModel.coreModel.setParameterValueById("ParamMouthOpenY", 0);
      },
      tap() { model.motion("TapBody", Math.floor(Math.random() * 3)); },
      cast() { model.motion("TapBody", spec.castMotion ?? 3, PIXI.live2d.MotionPriority.FORCE); },
      castPoint() {
        const [fx, fy] = spec.castFrom || [0.15, 0.07];
        return { x: model.x + model.width * fx, y: model.y + model.height * fy };
      },
      expr(name) { model.expression(name); },
    };
  }

  // ---- 图片角色：呼吸、蹦跳、抖动和头顶的情绪符号都由代码做 ----

  async function spriteActor(base, spec) {
    const images = spec.images || {};
    const textures = {};
    for (const [mood, file] of Object.entries(images)) textures[mood] = PIXI.Texture.from(base + file);
    await new Promise((r) => (textures.idle.baseTexture.valid ? r() : textures.idle.baseTexture.once("loaded", r)));
    const sprite = new PIXI.Sprite(textures.idle);
    sprite.anchor.set(0.5, 1);
    app.stage.addChild(sprite);
    const BADGES = { happy: "♪", excited: "✨", watching: "👀", angry: "💢", shy: "💗" };
    const badge = new PIXI.Text("", { fontSize: 22 });
    badge.anchor.set(0.5, 1);
    app.stage.addChild(badge);
    let mood = "idle";
    let t = 0;
    let hop = 0; // 蹦一下的剩余时间
    let speaking = false;
    let baseScale = 1;
    return {
      bounds: () => sprite.getBounds(),
      layout() {
        baseScale = spec.height / textures.idle.height;
        sprite.x = window.innerWidth / 2;
        sprite.y = window.innerHeight - 4;
      },
      tick(delta) {
        t += delta;
        const breathe = 1 + 0.018 * Math.sin(t * 0.06) + (speaking ? 0.012 * Math.abs(Math.sin(t * 0.4)) : 0);
        sprite.scale.set(baseScale * (1 + (breathe - 1) * 0.3), baseScale * breathe);
        const hopY = hop > 0 ? -Math.sin((1 - hop / 30) * Math.PI) * 18 : 0;
        if (hop > 0) hop -= delta;
        const shake = mood === "angry" ? Math.sin(t * 1.3) * 1.5 : 0;
        sprite.x = window.innerWidth / 2 + shake;
        sprite.y = window.innerHeight - 4 + hopY;
        const [hx, hy] = spec.headAt || [0.3, 0.1];
        const b = sprite.getBounds();
        badge.x = b.x + b.width * hx + 24;
        badge.y = b.y + b.height * hy + Math.sin(t * 0.1) * 2;
      },
      setMood(m) {
        mood = m;
        sprite.texture = textures[m] || textures.idle;
        badge.text = textures[m] ? "" : BADGES[m] || "";
      },
      setSpeaking(on) { speaking = on; },
      tap() { hop = 30; },
      cast() {
        hop = 30;
        if (textures.cast) {
          sprite.texture = textures.cast;
          setTimeout(() => (sprite.texture = textures[mood] || textures.idle), 1600);
        }
      },
      castPoint() {
        const [fx, fy] = spec.castFrom || [0.5, 0.5];
        const b = sprite.getBounds();
        return { x: b.x + b.width * fx, y: b.y + b.height * fy };
      },
      expr() {},
    };
  }

  async function load() {
    const base = `characters/${characterId}/`;
    const spec = await loadJSON(base + "character.json");
    actor = spec.kind === "live2d" ? await live2dActor(base, spec) : await spriteActor(base, spec);
    app.stage.addChild(effects);
    layout();
    window.addEventListener("resize", layout);
    app.ticker.add(tick);
    setMood(currentMood);
    post({ type: "ready", name: spec.name || characterId });
  }

  function layout() {
    actor?.layout();
    report();
  }

  function tick(delta) {
    actor?.tick(delta);
    for (const p of [...effects.children]) {
      if (p.life === undefined) continue;
      p.life -= delta;
      p.x += p.vx * delta;
      p.y += p.vy * delta;
      p.alpha = Math.max(0, p.life / p.maxLife);
      if (p.life <= 0) p.destroy();
    }
  }

  // ---- 对外接口 ----

  function setMood(mood) {
    currentMood = mood;
    actor?.setMood(mood);
  }

  function setSpeaking(on) { actor?.setSpeaking(on); }

  /** 对话气泡。buttons: [{id, title, style, waitSeconds}]；reasons: [{id, title}] */
  function say(text, buttons = [], reasons = []) {
    const bubble = document.getElementById("bubble");
    document.getElementById("text").textContent = text;
    const box = document.getElementById("buttons");
    const reasonBox = document.getElementById("reasons");
    box.innerHTML = "";
    reasonBox.innerHTML = "";
    delete reasonBox.dataset.done;
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

  /** 施法：角色做施法动作，星星从手边朝 (dx, dy) 方向飞出 */
  function cast(dx = -1, dy = -1) {
    if (!actor) return;
    actor.cast();
    const { x: ox, y: oy } = actor.castPoint();
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
  function burst(x, y) {
    if (x === undefined && actor) {
      const b = actor.bounds();
      x = b.x + b.width * 0.05;
      y = b.y - 30;
    }
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
    if (!actor) return;
    actor.tap();
    actor.setMood("shy");
    post({ type: "tapped" });
    clearTimeout(tapTimer);
    tapTimer = setTimeout(() => actor.setMood(currentMood), 2500);
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
    if (actor) {
      const b = actor.bounds();
      // 气泡的尾巴贴着角色头顶
      document.getElementById("bubble").style.bottom = `${Math.max(0, window.innerHeight - b.y + 6)}px`;
      rects.push({ x: b.x + b.width * 0.1, y: b.y + b.height * 0.05, w: b.width * 0.8, h: b.height * 0.95 });
    }
    const bubble = document.getElementById("bubble");
    if (!bubble.hidden) {
      const r = bubble.getBoundingClientRect();
      rects.push({ x: r.x, y: r.y, w: r.width, h: r.height + 10 });
    }
    post({ type: "hitRects", rects });
  }

  /** 开发用：直接切换 Live2D 的某个表情 */
  function expr(name) { actor?.expr(name); }

  window.mascot = { setMood, setSpeaking, say, hideBubble, cast, burst, tap, report, expr };
  load().catch((e) => post({ type: "error", message: String(e) }));
})();
