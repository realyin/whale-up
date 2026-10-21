// 桌宠：渲染角色（Live2D 模型或透明图片），提供表情、对话气泡、说话口型和施法特效。
// 角色包在 characters/<id>/character.json；Swift 通过 window.mascot.* 调用，网页通过 webkit.messageHandlers.mascot 回传事件。
(() => {
  const post = (msg) => window.webkit?.messageHandlers?.mascot?.postMessage(msg);
  const stage = document.getElementById("stage");
  const app = new PIXI.Application({ view: stage, backgroundAlpha: 0, resizeTo: window, antialias: true, autoDensity: true,
                                     resolution: window.devicePixelRatio || 2 });
  const effects = new PIXI.Container();
  const params = new URLSearchParams(location.search);
  const characterId = params.get("character") || "mao";
  // 窗口左右和下方留出的透明边（给圆环菜单用），她站在留边里面
  const [PADX, PADB] = (params.get("pad") || "0,0").split(",").map(Number);
  document.documentElement.style.setProperty("--padx", `${PADX}px`);
  let actor = null; // 当前角色驱动（Live2D 或图片）
  let characterSpec = null;
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
        model.y = window.innerHeight - PADB - model.height + model.height * 0.02;
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
      // Live2D 角色没有动作帧：睡觉时用闭眼的表情，其他动作不做
      play(name) {
        const exp = (spec.actionExpressions || {})[name];
        if (exp) { model.expression(exp); return {}; }
        return null;
      },
      stop() { this.setMood(currentMood); },
      actions: () => Object.keys(spec.actionExpressions || {}),
      isPlaying: () => false,
      castPoint() {
        const [fx, fy] = spec.castFrom || [0.15, 0.07];
        return { x: model.x + model.width * fx, y: model.y + model.height * fy };
      },
      expr(name) { model.expression(name); },
    };
  }

  // ---- 图片角色：呼吸、蹦跳、抖动、眨眼、部件摆动和头顶的情绪符号都由代码做 ----
  // character.json：images（各表情整张图，同一画布大小）、blink（闭眼帧）、
  // parts（单独摆动的部件：image、at=在画布上的左上角、pivot=部件内的旋转中心、swing=摆动角度、period=周期秒）

  // 每个动作的身体动态：s 是动作开始后的秒数，返回在角色身上叠加的位移/旋转/倾斜/缩放。
  // 图片角色只有几张关键帧，靠这些连续的动态让动作“活”起来，而不是两张图来回跳
  const wave = (s, period) => Math.sin((2 * Math.PI * s) / period);
  const bump = (s, hz) => Math.max(0, Math.sin(2 * Math.PI * hz * s));
  const rise = (s, seconds) => Math.sin(Math.PI * Math.min(1, s / seconds)); // 0 → 1 → 0
  const MOTIONS = {
    idle: (s) => ({ skew: 0.012 * wave(s, 4.2) }),
    eat: (s) => ({ y: -2.5 * bump(s, 1.2), rot: 0.015 * wave(s, 1.7) }),
    sleep: (s) => ({ sy: 0.022 * wave(s, 3.6), rot: 0.02 * wave(s, 7) }),
    yawn: (s) => ({ sy: 0.05 * rise(s, 2.2), sx: -0.02 * rise(s, 2.2), skew: 0.02 * wave(s, 2.4) }),
    stretch: (s) => ({ sy: 0.06 * rise(s, 2.6), sx: -0.025 * rise(s, 2.6), skew: 0.05 * wave(s, 2.6) }),
    swim: (s) => ({ x: 12 * wave(s, 3), y: 5 * wave(s, 1.5), rot: 0.06 * Math.cos((2 * Math.PI * s) / 3) }),
    dance: (s) => ({ y: -9 * Math.abs(Math.sin(Math.PI * 2.2 * s)), rot: 0.07 * Math.sin(Math.PI * 2.2 * s), skew: 0.04 * wave(s, 1.8) }),
    work: (s) => ({ y: -1.2 * bump(s, 5), rot: 0.01 * wave(s, 3) }),
    heart: (s) => ({ y: -3 * bump(s, 1.6), sx: 0.04 * bump(s, 1.6), sy: 0.04 * bump(s, 1.6) }),
    milktea: (s) => ({ y: -2 * wave(s, 1.8), rot: 0.02 * wave(s, 3.6) }),
    read: (s) => ({ y: -1 * wave(s, 2), rot: 0.025 * wave(s, 4) }),
  };
  const smooth = (x) => x * x * (3 - 2 * x);

  async function spriteActor(base, spec) {
    const textures = {};
    for (const [mood, file] of Object.entries(spec.images || {})) textures[mood] = PIXI.Texture.from(base + file);
    const blinkTexture = spec.blink ? PIXI.Texture.from(base + spec.blink) : null;
    // 动作：{ frames: [...], fps, seconds, loop, effect, ownPose }，或者 { variants: [同样的写法…] } 每次随机挑一种
    const actions = {};
    for (const [name, a] of Object.entries(spec.actions || {})) {
      const variants = a.variants || [a];
      actions[name] = variants.map((v) => ({ ...v, textures: v.frames.map((f) => PIXI.Texture.from(base + f)) }));
    }
    let action = null; // { name, def, started }
    const loaded = (tex) => new Promise((r) => (tex.baseTexture.valid ? r() : tex.baseTexture.once("loaded", r)));
    await loaded(textures.idle);

    // 整个角色放在一个容器里，呼吸、摇摆时部件一起动
    const rig = new PIXI.Container();
    const body = new PIXI.Sprite(textures.idle);
    // 所有帧按底部中心对齐：同画布的表情帧位置不变，新姿势的帧站在同一个地面上
    body.anchor.set(0.5, 1);
    body.position.set(textures.idle.width / 2, textures.idle.height);
    rig.addChild(body);
    // 换图时旧图盖在上面慢慢淡出，换姿势不再“咔”地一跳
    const ghost = new PIXI.Sprite(textures.idle);
    ghost.anchor.set(0.5, 1);
    ghost.position.copyFrom(body.position);
    ghost.alpha = 0;
    rig.addChild(ghost);
    let fadeRate = 0;
    const setTexture = (tex, seconds = 0.18) => {
      if (body.texture === tex) return;
      if (seconds > 0) {
        ghost.texture = body.texture;
        ghost.alpha = 1;
        fadeRate = 1 / (seconds * 60);
      }
      else ghost.alpha = 0;
      body.texture = tex;
    };

    const parts = [];
    for (const p of spec.parts || []) {
      const tex = PIXI.Texture.from(base + p.image);
      await loaded(tex);
      const sprite = new PIXI.Sprite(tex);
      sprite.pivot.set(p.pivot[0], p.pivot[1]);
      sprite.position.set(p.at[0] + p.pivot[0], p.at[1] + p.pivot[1]);
      rig.addChildAt(sprite, 0); // 部件画在身体后面（尾巴从裙子下面伸出来）
      parts.push({ sprite, swing: ((p.swing || 5) * Math.PI) / 180, period: p.period || 2.4, phase: Math.random() * 6 });
    }
    const W = textures.idle.width;
    const H = textures.idle.height;
    rig.pivot.set(W / 2, H);
    app.stage.addChild(rig);

    const BADGES = { happy: "♪", excited: "✨", watching: "👀", angry: "💢", shy: "💗" };
    const badge = new PIXI.Text("", { fontSize: 22 });
    badge.anchor.set(0.5, 1);
    app.stage.addChild(badge);

    let mood = "idle";
    let t = 0;
    let hop = 0;
    let pop = 0; // 换动作时的“弹一下”（先压扁再回弹），1 → 0
    let popAmp = 1;
    const kick = (amp) => { pop = 1; popAmp = amp; };
    let speaking = false;
    let speakAmp = 0;
    let baseScale = 1;
    let casting = false;
    let blinkLeft = 0;
    let nextBlink = 180 + Math.random() * 200;
    // 当前动态和正在淡出的上一个动态，两者交叉过渡
    const now = () => performance.now() / 1000;
    let motion = { fn: MOTIONS.idle, from: now(), fadeIn: 0.01 };
    let leaving = null;
    const switchMotion = (fn) => {
      leaving = { ...motion, until: now() + 0.4 };
      motion = { fn, from: now(), fadeIn: 0.4 };
      kick(1);
    };
    const actionTexture = () => {
      if (!action) return null;
      const elapsed = now() - action.started;
      const frames = action.def.textures;
      return frames[Math.floor(elapsed * (action.def.fps || 1)) % frames.length];
    };
    const faceTexture = () => (casting && textures.cast) || actionTexture() || textures[mood] || textures.idle;
    const endAction = () => {
      action = null;
      switchMotion(MOTIONS.idle);
    };

    return {
      bounds: () => rig.getBounds(),
      layout() { baseScale = spec.height / H; },
      tick(delta) {
        t += delta;
        const s = now();

        // 动作播放：到时间就结束；帧之间淡入淡出
        if (action) {
          const elapsed = s - action.started;
          if (!action.def.loop && elapsed > (action.def.seconds || 3)) {
            const ended = action.name;
            endAction();
            stopEffect();
            post({ type: "actionEnded", name: ended });
            setTexture(faceTexture(), 0);
          } else if (!casting && body.texture !== faceTexture()) {
            // 关键帧之间直接切（交叉淡化会出现两张图叠在一起的“重影”），
            // 切换点正好落在动态的节拍上，再配一下压扁回弹，看起来是“跳”到下一个姿势
            setTexture(faceTexture(), 0);
            kick(0.5);
          }
        }
        if (ghost.alpha > 0) ghost.alpha = Math.max(0, ghost.alpha - fadeRate * delta);

        // 叠加动态：当前动态淡入，上一个淡出
        const m = { x: 0, y: 0, rot: 0, skew: 0, sx: 0, sy: 0 };
        const add = (part, w) => { for (const k in part) m[k] += part[k] * w; };
        add(motion.fn(s - motion.from), smooth(Math.min(1, (s - motion.from) / motion.fadeIn)));
        if (leaving) {
          const w = (leaving.until - s) / 0.4;
          if (w <= 0) leaving = null;
          else add(leaving.fn(s - leaving.from), smooth(w));
        }

        // 呼吸；说话时轻轻点头（平滑起落，不抖）
        speakAmp += ((speaking ? 1 : 0) - speakAmp) * Math.min(1, 0.12 * delta);
        const breathe = 0.018 * Math.sin(s * 3.6);
        const talk = speakAmp * (0.5 - 0.5 * Math.cos(s * 2 * Math.PI * 2.6));
        // 弹一下：衰减的振荡
        if (pop > 0) pop = Math.max(0, pop - delta / 27);
        const squash = pop > 0 ? Math.sin((1 - pop) * Math.PI * 3) * pop * 0.07 * popAmp : 0;
        const sy = 1 + breathe + talk * 0.012 + m.sy - squash;
        const sx = 1 + breathe * 0.3 + m.sx + squash;
        rig.scale.set(baseScale * sx, baseScale * sy);
        rig.rotation = m.rot;
        rig.skew.x = m.skew;

        const hopY = hop > 0 ? -Math.sin((1 - hop / 30) * Math.PI) * 18 : 0;
        if (hop > 0) hop -= delta;
        const shake = mood === "angry" && !textures.angry ? Math.sin(t * 1.3) * 1.5 : 0;
        rig.position.set(window.innerWidth / 2 + shake + m.x, window.innerHeight - PADB - 4 + hopY + m.y - talk * 1.5);

        // 部件摆动（生气时摆得更快）；新姿势的图自带尾巴，这时把单独的尾巴藏起来
        const speed = mood === "angry" ? 2.2 : 1;
        const ownPose = action && action.def.ownPose;
        for (const p of parts) {
          p.sprite.rotation = Math.sin((t / 60) * ((2 * Math.PI) / p.period) * speed + p.phase) * p.swing;
          p.sprite.visible = !ownPose;
        }

        // 眨眼：只在用平时那张脸时眨（眨眼本来就是一下子，不淡入淡出）
        if (blinkTexture && !casting && !action && faceTexture() === textures.idle) {
          if (blinkLeft > 0) {
            blinkLeft -= delta;
            setTexture(blinkLeft > 0 ? blinkTexture : textures.idle, 0);
          } else if ((nextBlink -= delta) <= 0) {
            blinkLeft = 8;
            nextBlink = 180 + Math.random() * 200;
          }
        }

        const [hx, hy] = spec.headAt || [0.3, 0.1];
        const b = rig.getBounds();
        badge.x = b.x + b.width * hx + 24;
        badge.y = b.y + b.height * hy + Math.sin(t * 0.1) * 2;
      },
      setMood(m) {
        mood = m;
        setTexture(faceTexture(), 0.2);
        badge.text = textures[m] || action ? "" : BADGES[m] || "";
      },
      actions: () => Object.keys(actions),
      isPlaying: (name) => action?.name === name,
      play(name, index) {
        const variants = actions[name];
        if (!variants) return null;
        const def = variants[index ?? Math.floor(Math.random() * variants.length)] || variants[0];
        action = { name, def, started: now() };
        badge.text = "";
        switchMotion(MOTIONS[name] || MOTIONS.idle);
        setTexture(faceTexture(), 0);
        return def;
      },
      stop() {
        if (action) endAction();
        this.setMood(mood);
      },
      setSpeaking(on) { speaking = on; },
      tap() { hop = 30; kick(1); },
      cast() {
        hop = 30;
        if (!textures.cast) return;
        casting = true;
        setTexture(faceTexture(), 0.12);
        setTimeout(() => { casting = false; setTexture(faceTexture(), 0.25); }, 1800);
      },
      castPoint() {
        const [fx, fy] = (textures.cast && spec.castFromCast) || spec.castFrom || [0.5, 0.5];
        const b = rig.getBounds();
        return { x: b.x + b.width * fx, y: b.y + b.height * fy };
      },
      expr() {},
    };
  }

  /** 气泡配色和名牌跟着角色：theme 里的键对应 mascot.css 的 CSS 变量 */
  function applyTheme(spec) {
    for (const [k, v] of Object.entries(spec.theme || {})) document.documentElement.style.setProperty(`--${k}`, v);
    document.getElementById("name").textContent = spec.nickname || "";
  }

  async function load() {
    const base = `characters/${characterId}/`;
    const spec = await loadJSON(base + "character.json");
    characterSpec = spec;
    applyTheme(spec);
    actor = spec.kind === "live2d" ? await live2dActor(base, spec) : await spriteActor(base, spec);
    app.stage.addChild(effects);
    layout();
    window.addEventListener("resize", layout);
    app.ticker.add(tick);
    setMood(currentMood);
    post({ type: "ready", name: spec.name || characterId, actions: actor.actions() });
  }

  function layout() {
    actor?.layout();
    report();
  }

  let lastRects = "";
  function tick(delta) {
    actor?.tick(delta);
    report();
    for (const p of [...effects.children]) {
      if (p.life === undefined) continue;
      p.life -= delta;
      p.x += p.vx * delta;
      p.y += p.vy * delta;
      if (p.gravity) p.vy += p.gravity * delta;
      if (p.drag) { p.vx *= Math.pow(p.drag, delta); p.vy *= Math.pow(p.drag, delta); }
      // 离窗口边越近越透明，飞出去的星星不会被窗口边“切”出一条直线
      const edge = Math.min(p.x, window.innerWidth - p.x, p.y, window.innerHeight - p.y);
      p.alpha = Math.max(0, p.life / p.maxLife) * Math.max(0, Math.min(1, edge / 60));
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
        // 星星喷出去后慢慢减速，像一道拖尾，在窗口里就散开淡掉
        for (let i = 0; i < 8; i++) star(ox, oy, (dx / len) * (6 + Math.random() * 7) + (Math.random() - 0.5) * 5,
                                       (dy / len) * (6 + Math.random() * 7) + (Math.random() - 0.5) * 5, 75, 0.982, 1.25);
        if (++n > 20) clearInterval(timer);
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
    for (let i = 0; i < 70; i++) {
      const a = Math.random() * Math.PI * 2;
      const v = 3 + Math.random() * 7;
      star(x, y, Math.cos(a) * v, Math.sin(a) * v, 75, 0.975, 1.25);
    }
  }

  const COLORS = [0xff6fa8, 0xffd84d, 0x9be7ff, 0xc9a2ff, 0xffffff];
  function star(x, y, vx, vy, life, drag, scale = 1) {
    const g = new PIXI.Graphics();
    const outer = (4 + Math.random() * 6) * scale;
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
    Object.assign(g, { x, y, vx, vy, life, maxLife: life, drag });
    effects.addChild(g);
  }

  // 被戳一下：害羞地动一动，过一会儿恢复
  let tapTimer = null;
  function tap() {
    if (!actor) return;
    if (playingName === "sleep") {
      stop();
      post({ type: "woke" });
      return;
    }
    actor.tap();
    actor.setMood("shy");
    post({ type: "tapped" });
    clearTimeout(tapTimer);
    tapTimer = setTimeout(() => actor.setMood(currentMood), 2500);
  }

  // ---- 右键圆环菜单：功能围着她弹出一圈，点“动作”等再展开第二圈 ----
  // spec：{ status, items: [{ id, title, icon, on, disabled, hint, children: [...] }], visible: {x, y, w, h} }
  // visible 是屏幕可用区域（窗口坐标），靠近屏幕边时圆环变成朝屏幕里的一段弧

  const ringEl = document.getElementById("ring");
  let ring = null; // { spec, stack: [items...], openedAt }

  /** 圆心：她身体的中心 */
  function ringCenter() {
    const b = actor.bounds();
    return { x: b.x + b.width / 2, y: b.y + b.height * 0.52, body: Math.hypot(b.width, b.height) * 0.42 };
  }

  /** 在 [x0, x1] × [y0, y1] 里给 n 个泡泡找位置：先放内圈，放不下再放外圈；
   *  圈上被屏幕边挡住的部分不用，泡泡集中在最长的那段能用的弧上 */
  function ringPositions(n, c, box, size, labelWidth = 0) {
    // 相邻泡泡至少隔开一个泡泡或一条名字缎带的宽度
    const spacing = Math.max(size + 16, labelWidth + 10);
    const half = size / 2 + 4;
    const fits = (r, a) => {
      const x = c.x + r * Math.cos(a);
      const y = c.y + r * Math.sin(a);
      return x - half > box.x0 && x + half < box.x1 && y - half > box.y0 && y + half + 18 < box.y1;
    };
    // 一圈能放几个：整圈、或最长那段能用的弧
    const arc = (r) => {
      const step = Math.PI / 60;
      const ok = [];
      for (let i = 0; i < 120; i++) ok.push(fits(r, -Math.PI + i * step));
      if (ok.every(Boolean)) return Math.floor((2 * Math.PI * r) / spacing);
      let best = 0;
      for (let i = 0; i < 120; i++) {
        if (!ok[i] || ok[(i + 119) % 120]) continue;
        let len = 0;
        while (len < 120 && ok[(i + len) % 120]) len++;
        best = Math.max(best, len);
      }
      return best ? Math.floor(((best - 1) * step * r) / spacing) + 1 : 0;
    };
    const rows = [];
    let left = n;
    // 内圈离开她的身体；放不下时先把这一圈撑大一点（最多 50px），还不行再开外圈
    let r0 = Math.max(size * 2.1 + 4, c.body + size / 2 + 8);
    for (let grow = 0; grow <= 50; grow += 10) if (arc(r0 + grow) >= n) { r0 += grow; break; }
    for (const r of [r0, r0 + size + 22, r0 + 2 * (size + 22)]) {
      if (left <= 0) break;
      const step = Math.PI / 60;
      const ok = [];
      for (let i = 0; i < 120; i++) ok.push(fits(r, -Math.PI + i * step));
      let full = ok.every(Boolean);
      // 找最长的连续可用段（首尾相接）
      let best = { start: 0, len: 0 };
      if (!full) {
        for (let i = 0; i < 120; i++) {
          if (!ok[i] || ok[(i + 119) % 120]) continue;
          let len = 0;
          while (len < 120 && ok[(i + len) % 120]) len++;
          if (len > best.len) best = { start: i, len };
        }
        if (!best.len) continue;
      }
      const span = full ? 2 * Math.PI : (best.len - 1) * step;
      const cap = full ? Math.floor((2 * Math.PI * r) / spacing) : Math.floor((span * r) / spacing) + 1;
      if (cap <= 0) continue;
      const k = Math.min(left, cap);
      left -= k;
      if (full) {
        for (let i = 0; i < k; i++) rows.push({ r, a: -Math.PI / 2 + (i * 2 * Math.PI) / k });
      } else {
        // 泡泡挨着排在弧的中间，不铺满整段弧
        const mid = -Math.PI + (best.start + (best.len - 1) / 2) * step;
        const da = spacing / r;
        for (let i = 0; i < k; i++) rows.push({ r, a: mid + (i - (k - 1) / 2) * da });
      }
    }
    // 实在放不下的（屏幕太小）叠在最后一圈上
    while (rows.length < n) rows.push({ ...rows[rows.length - 1] });
    return rows.map(({ r, a }) => ({ x: c.x + r * Math.cos(a), y: c.y + r * Math.sin(a) }));
  }

  function renderRing(items, back) {
    ringEl.innerHTML = "";
    const c = ringCenter();
    const v = ring.spec.visible || { x: 0, y: 0, w: window.innerWidth, h: window.innerHeight };
    const box = { x0: Math.max(0, v.x), y0: Math.max(0, v.y),
                  x1: Math.min(window.innerWidth, v.x + v.w), y1: Math.min(window.innerHeight, v.y + v.h) };
    const size = items.length > 7 ? 36 : 40;
    const measure = document.createElement("canvas").getContext("2d");
    measure.font = "700 9.5px -apple-system, 'PingFang SC', sans-serif";
    const labelWidth = Math.max(...items.map((it) => measure.measureText((it.on ? "✓ " : "") + it.title).width + 14));
    const pos = ringPositions(items.length, c, box, size, labelWidth);

    items.forEach((it, i) => {
      const el = document.createElement("button");
      el.className = "ri" + (it.on ? " on" : "") + (it.children ? " group" : "");
      el.disabled = !!it.disabled;
      el.style.setProperty("--size", `${size}px`);
      el.style.left = `${c.x}px`;
      el.style.top = `${c.y}px`;
      el.innerHTML = `<span class="ic"></span><span class="lb"></span>`;
      // 角色包里画好的图标优先（character.json 的 icons：{项目 id: 图片}），没有再用 emoji
      const art = (characterSpec.icons || {})[it.id];
      if (art) {
        const img = document.createElement("img");
        img.src = `characters/${characterId}/${art}`;
        el.querySelector(".ic").appendChild(img);
      } else el.querySelector(".ic").textContent = it.icon || "•";
      el.querySelector(".lb").textContent = it.title;
      if (it.hint) el.title = it.hint;
      el.onclick = (e) => { e.stopPropagation(); pick(it); };
      ringEl.appendChild(el);
      // 从她身上一个接一个弹出去
      setTimeout(() => {
        el.classList.add("out");
        el.style.left = `${pos[i].x}px`;
        el.style.top = `${pos[i].y}px`;
      }, 16 + i * 22);
    });

    // 顶上（或下面）一条小缎带：今天的情况，第二圈时提示“点她返回”
    const top = Math.min(...pos.map((p) => p.y)) - size / 2;
    const bottom = Math.max(...pos.map((p) => p.y)) + size / 2 + 20;
    const pill = document.createElement("div");
    pill.className = "ring-status";
    pill.textContent = back ? `${back} · 点她返回` : ring.spec.status || "";
    pill.style.left = `${c.x}px`;
    pill.style.top = top - 26 > box.y0 ? `${top - 26}px` : `${Math.min(bottom + 4, box.y1 - 22)}px`;
    if (pill.textContent) ringEl.appendChild(pill);
  }

  function openRing(spec) {
    if (!actor) return;
    clearTimeout(ringCloseTimer);
    ring = { spec, stack: [], openedAt: performance.now() };
    document.body.classList.add("ring-open");
    renderRing(spec.items);
    actor.tap?.();
    report();
  }

  let ringCloseTimer = null;
  function closeRing() {
    if (!ring) return;
    ring = null;
    for (const el of ringEl.querySelectorAll(".ri")) {
      el.classList.remove("out");
      const c = ringCenter();
      el.style.left = `${c.x}px`;
      el.style.top = `${c.y}px`;
    }
    ringEl.querySelector(".ring-status")?.remove();
    ringCloseTimer = setTimeout(() => { ringEl.innerHTML = ""; }, 220);
    document.body.classList.remove("ring-open");
    post({ type: "ringClosed" });
    report();
  }

  function pick(it) {
    if (!ring || it.disabled) return;
    if (it.children) {
      ring.stack.push(it);
      renderRing(it.children, it.note || it.title);
      return;
    }
    closeRing();
    post({ type: "ring", id: it.id });
  }

  /** 点她：在第二圈时回到第一圈，否则收起 */
  function ringBack() {
    if (!ring) return;
    if (ring.stack.length) {
      ring.stack.pop();
      const parent = ring.stack[ring.stack.length - 1];
      renderRing(parent ? parent.children : ring.spec.items, parent && (parent.note || parent.title));
    } else closeRing();
  }

  function insideHer(x, y) {
    const b = actor.bounds();
    return x > b.x && x < b.x + b.width && y > b.y && y < b.y + b.height;
  }

  // ---- 鼠标：拖动窗口、点角色、右键圆环、告诉 Swift 哪里可以点穿 ----

  // 右键按下：弹出圆环（按住拖到某一项上松开也能直接选）
  document.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    drag = null;
    if (ring) { closeRing(); return; }
    post({ type: "menu", option: e.altKey });
  });
  window.addEventListener("mouseup", (e) => {
    if (e.button !== 2 || !ring || performance.now() - ring.openedAt < 250) return;
    const el = document.elementFromPoint(e.clientX, e.clientY)?.closest(".ri");
    el?.click();
  });

  let drag = null;
  document.addEventListener("mousedown", (e) => {
    if (ring) {
      // 圆环打开时：点她返回/收起，点空白处收起；点泡泡交给泡泡自己
      if (e.button !== 0 || e.target.closest(".ri")) return;
      if (insideHer(e.clientX, e.clientY)) ringBack();
      else closeRing();
      return;
    }
    if (e.button !== 0 || e.target.closest("#bubble")) return;
    drag = { x: e.screenX, y: e.screenY, moved: false };
  });
  window.addEventListener("keydown", (e) => { if (e.key === "Escape") closeRing(); });
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
    // 圆环打开时整个窗口都接收鼠标（点空白处收起）
    if (ring) rects.push({ x: 0, y: 0, w: window.innerWidth, h: window.innerHeight });
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
    // 每帧算一次，变了才告诉 Swift（加载、换姿势、施法飞行时角色大小位置都会变）
    const key = JSON.stringify(rects.map((r) => [r.x, r.y, r.w, r.h].map((v) => Math.round(v / 8))));
    if (key === lastRects) return;
    lastRects = key;
    post({ type: "hitRects", rects });
  }

  // ---- 动作：打哈欠、睡觉、伸懒腰、吃饭 ----

  let effectTimer = null;
  let playingName = null;
  const EFFECTS = { zzz: [zzz, 1100], rice: [rice, 700], bubbles: [bubble, 500], notes: [note, 600], hearts: [heart, 450] };
  /** 播放动作；特效优先用角色包里写的，其次用传进来的 */
  function play(name, effect, index) {
    if (!actor) return;
    const def = actor.play(name, index) || {};
    playingName = name;
    stopEffect();
    const e = EFFECTS[def.effect || effect];
    if (e) effectTimer = setInterval(e[0], e[1]);
  }

  function stopEffect() {
    clearInterval(effectTimer);
    effectTimer = null;
  }

  function stop() {
    stopEffect();
    playingName = null;
    actor?.stop();
  }

  function floatText(text, color, size, dx) {
    const b = actor.bounds();
    const t = new PIXI.Text(text, { fontSize: size, fill: color, fontWeight: "700" });
    Object.assign(t, { x: b.x + b.width * (0.3 + Math.random() * 0.4), y: b.y + b.height * 0.2,
                       vx: dx + (Math.random() - 0.5) * 0.4, vy: -0.7, life: 90, maxLife: 90 });
    effects.addChild(t);
  }
  function note() { floatText(Math.random() < 0.5 ? "♪" : "♫", 0xff6fa8, 18 + Math.random() * 6, 0.3); }
  function heart() { floatText("❤", 0xff4f8b, 14 + Math.random() * 10, 0); }

  function bubble() {
    const b = actor.bounds();
    const g = new PIXI.Graphics();
    const r = 3 + Math.random() * 5;
    g.lineStyle(1.5, 0x8fd3ff, 0.9);
    g.beginFill(0xd8f1ff, 0.35);
    g.drawCircle(0, 0, r);
    g.endFill();
    Object.assign(g, { x: b.x + b.width * (0.2 + Math.random() * 0.6), y: b.y + b.height * 0.5,
                       vx: (Math.random() - 0.5) * 0.4, vy: -0.8 - Math.random() * 0.5, life: 100, maxLife: 100 });
    effects.addChild(g);
  }

  function zzz() {
    const b = actor.bounds();
    const z = new PIXI.Text(Math.random() < 0.5 ? "z" : "Z", { fontSize: 14 + Math.random() * 8, fill: 0x6b7fd7, fontWeight: "700" });
    Object.assign(z, { x: b.x + b.width * 0.3, y: b.y + b.height * 0.15, vx: 0.35 + Math.random() * 0.2, vy: -0.6, life: 110, maxLife: 110 });
    effects.addChild(z);
  }

  function rice() {
    if (Math.random() < 0.4) return;
    const b = actor.bounds();
    const g = new PIXI.Graphics();
    g.beginFill(0xffffff);
    g.lineStyle(1, 0xd8d0c0);
    g.drawEllipse(0, 0, 2.2, 3.2);
    g.endFill();
    g.rotation = Math.random() * Math.PI;
    Object.assign(g, { x: b.x + b.width * 0.42, y: b.y + b.height * 0.45, vx: (Math.random() - 0.5) * 1.5, vy: -1.5 - Math.random(), gravity: 0.12, life: 40, maxLife: 40 });
    effects.addChild(g);
  }

  /** 开发用：直接切换 Live2D 的某个表情 */
  function expr(name) { actor?.expr(name); }

  window.mascot = { setMood, setSpeaking, say, hideBubble, cast, burst, tap, report, expr, play, stop, openRing, closeRing };
  load().catch((e) => post({ type: "error", message: String(e) }));
})();
