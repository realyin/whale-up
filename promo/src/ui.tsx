import React from "react";
import { interpolate, random, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, FONT } from "./theme";

/** 底部字幕：白字深蓝描边，B 站常见的样子 */
export const Subtitle = ({ text }: { text: string }) => (
  <div style={{
    position: "absolute", left: 0, right: 0, bottom: 56, textAlign: "center", fontFamily: FONT,
    fontSize: 46, fontWeight: 800, color: "#fff", letterSpacing: 2,
    textShadow: `0 0 2px ${C.ink}, 3px 3px 0 ${C.ink}, -3px 3px 0 ${C.ink}, 3px -3px 0 ${C.ink}, -3px -3px 0 ${C.ink}, 0 6px 14px rgba(0,0,0,.35)`,
  }}>{text}</div>
);

/** 她的对话气泡：和桌宠里一样的女仆风——奶白底、深蓝描边、顶上蕾丝、左上名牌 */
export const Bubble = ({ text, x, y, width = 460, from = 0, name = "大肥鱼" }:
  { text: string; x: number; y: number; width?: number; from?: number; name?: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: frame - from, fps, config: { damping: 11, stiffness: 180 } });
  if (frame < from) return null;
  return (
    <div style={{
      position: "absolute", left: x - width / 2, bottom: 1080 - y, width, fontFamily: FONT,
      transform: `scale(${pop})`, transformOrigin: "50% 100%",
    }}>
      <div style={{
        position: "relative", background: C.paper, border: `4px solid ${C.ink}`, borderRadius: 26,
        padding: "30px 26px 22px", color: C.ink, fontSize: 34, fontWeight: 700, lineHeight: 1.45,
        boxShadow: "0 6px 0 rgba(0,0,0,.12), 0 14px 30px rgba(20,30,70,.25)",
      }}>
        <div style={{ position: "absolute", inset: 7, border: "2.5px dashed rgba(61,111,214,.4)", borderRadius: 19 }} />
        <div style={{
          position: "absolute", left: 22, right: 22, top: -13, height: 14,
          background: `radial-gradient(circle at 9px 14px, #fff 7px, ${C.ink} 7.5px 10px, transparent 10.5px) 0 0 / 19px 14px repeat-x`,
        }} />
        <div style={{
          position: "absolute", left: 22, top: -22, background: C.ink, color: C.paper, fontSize: 20,
          padding: "2px 14px 4px", borderRadius: 10, fontWeight: 800, letterSpacing: 1,
        }}>{name}</div>
        <div style={{
          position: "absolute", left: "50%", bottom: -15, width: 24, height: 24, marginLeft: -12, background: C.paper,
          borderRight: `4px solid ${C.ink}`, borderBottom: `4px solid ${C.ink}`, transform: "rotate(45deg)",
        }} />
        <span style={{ position: "relative" }}>{text}</span>
      </div>
    </div>
  );
};

/** macOS 的鼠标箭头 */
export const Cursor = ({ x, y, pressed = false }: { x: number; y: number; pressed?: boolean }) => (
  <svg width="44" height="58" viewBox="0 0 22 29" style={{
    position: "absolute", left: x, top: y, transform: `scale(${pressed ? 0.85 : 1})`, transformOrigin: "0 0",
    filter: "drop-shadow(0 3px 4px rgba(0,0,0,.35))",
  }}>
    <path d="M1 1 L1 23 L6.5 17.5 L10.5 27 L14 25.5 L10 16.5 L18 16.5 Z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

const STAR_COLORS = ["#ff6fa8", "#ffd84d", "#9be7ff", "#c9a2ff", "#ffffff"];
const starPath = (r: number) => {
  const pts: string[] = [];
  for (let i = 0; i < 10; i++) {
    const rr = i % 2 ? r * 0.45 : r;
    const a = (Math.PI / 5) * i - Math.PI / 2;
    pts.push(`${Math.cos(a) * rr},${Math.sin(a) * rr}`);
  }
  return `M${pts.join("L")}Z`;
};

/** 魔法星星：从 (x, y) 朝 (dx, dy) 喷出去（burst 时四面八方炸开），慢慢减速、淡出 */
export const Stars = ({ x, y, from, dx = -1, dy = -0.7, burst = false, count = 140, spread = 26, seed = "s" }:
  { x: number; y: number; from: number; dx?: number; dy?: number; burst?: boolean; count?: number; spread?: number; seed?: string }) => {
  const frame = useCurrentFrame();
  const len = Math.hypot(dx, dy) || 1;
  const drag = 0.955;
  const life = 46;
  const items: React.ReactNode[] = [];
  for (let i = 0; i < count; i++) {
    const born = from + (burst ? 0 : Math.floor((i / count) * spread));
    const t = frame - born;
    if (t < 0 || t > life) continue;
    const r = (k: string) => random(`${seed}-${i}-${k}`);
    let vx: number, vy: number;
    if (burst) {
      const a = r("a") * Math.PI * 2;
      const v = 8 + r("v") * 22;
      vx = Math.cos(a) * v; vy = Math.sin(a) * v;
    } else {
      const v = 18 + r("v") * 20;
      vx = (dx / len) * v + (r("x") - 0.5) * 14;
      vy = (dy / len) * v + (r("y") - 0.5) * 14;
    }
    const travel = (1 - Math.pow(drag, t)) / (1 - drag);
    const size = 10 + r("s") * 18;
    items.push(
      <path key={i} d={starPath(size)} fill={STAR_COLORS[Math.floor(r("c") * STAR_COLORS.length)]}
        transform={`translate(${x + vx * travel} ${y + vy * travel + 0.05 * t * t}) rotate(${r("r") * 180 + t * 6})`}
        opacity={1 - t / life} />,
    );
  }
  return <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>{items}</svg>;
};

/** 屏幕顶上的 Mac 菜单栏 */
export const MenuBar = ({ time }: { time: string }) => (
  <div style={{
    position: "absolute", left: 0, right: 0, top: 0, height: 44, background: "rgba(20,24,48,.55)", backdropFilter: "blur(20px)",
    display: "flex", alignItems: "center", padding: "0 26px", gap: 30, color: "#fff", fontFamily: FONT, fontSize: 21, fontWeight: 600,
  }}>
    <span style={{ fontSize: 24 }}></span><span style={{ fontWeight: 800 }}>刷刷看</span><span>文件</span><span>编辑</span><span>显示</span>
    <span style={{ flex: 1 }} />
    <span>👀 47′</span><span>{time}</span>
  </div>
);

/** 浏览器窗口 */
export const Browser = ({ x, y, w, h, title, url, children, style }:
  { x: number; y: number; w: number; h: number; title: string; url: string; children?: React.ReactNode; style?: React.CSSProperties }) => (
  <div style={{
    position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 18, overflow: "hidden", fontFamily: FONT,
    background: "#14161f", boxShadow: "0 30px 80px rgba(0,0,0,.5), 0 0 0 1px rgba(255,255,255,.12)", ...style,
  }}>
    <div style={{ height: 52, background: "#262a36", display: "flex", alignItems: "center", gap: 10, padding: "0 18px" }}>
      {["#ff5f57", "#febc2e", "#28c840"].map((c) => <span key={c} style={{ width: 15, height: 15, borderRadius: 8, background: c }} />)}
      <div style={{
        marginLeft: 16, background: "#14161f", color: "#dfe3ee", fontSize: 18, padding: "8px 18px", borderRadius: "10px 10px 0 0",
        alignSelf: "flex-end", minWidth: 220,
      }}>{title}</div>
      <div style={{ flex: 1, marginLeft: 12, background: "#1a1d27", color: "#8b93a8", fontSize: 17, padding: "7px 16px", borderRadius: 9 }}>{url}</div>
    </div>
    <div style={{ position: "absolute", top: 52, left: 0, right: 0, bottom: 0, overflow: "hidden" }}>{children}</div>
  </div>
);

const FEED = [
  { t: "猫猫翻车合集 第 47 集", c: ["#ff9a8b", "#ff6a88"], k: "2.3 万" },
  { t: "三秒教你月入十万（真的）", c: ["#f6d365", "#fda085"], k: "8.1 万" },
  { t: "挑战一口吃掉一整个西瓜", c: ["#84fab0", "#8fd3f4"], k: "4.7 万" },
  { t: "这个转折我真的没想到", c: ["#a18cd1", "#fbc2eb"], k: "12 万" },
  { t: "沉浸式收拾房间 4 小时", c: ["#fccb90", "#d57eeb"], k: "6.6 万" },
  { t: "狗狗第一次见到雪", c: ["#89f7fe", "#66a6ff"], k: "9.9 万" },
  { t: "全网最难的十个谜题", c: ["#fddb92", "#d1fdff"], k: "3.1 万" },
];

/** 短视频流：每隔一会儿往上划一条 */
export const Feed = ({ every = 22, offset = 0 }: { every?: number; offset?: number }) => {
  const frame = useCurrentFrame() + offset;
  const { fps } = useVideoConfig();
  const n = Math.floor(frame / every);
  const p = spring({ frame: frame - n * every, fps, config: { damping: 18, stiffness: 160 } });
  const pos = n - 1 + p;
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {[-1, 0, 1].map((d) => {
        const i = Math.floor(pos) + d;
        const item = FEED[((i % FEED.length) + FEED.length) % FEED.length];
        const top = (i - pos) * 100;
        return (
          <div key={i} style={{
            position: "absolute", left: 0, right: 0, top: `${top}%`, height: "100%",
            background: `linear-gradient(135deg, ${item.c[0]}, ${item.c[1]})`, display: "flex", flexDirection: "column",
            justifyContent: "flex-end", padding: 40, color: "#fff",
          }}>
            <div style={{ position: "absolute", left: "50%", top: "40%", transform: "translate(-50%,-50%)", width: 110, height: 110,
              borderRadius: 60, background: "rgba(255,255,255,.35)", display: "flex", alignItems: "center", justifyContent: "center" }}>
              <div style={{ width: 0, height: 0, borderTop: "26px solid transparent", borderBottom: "26px solid transparent",
                borderLeft: "42px solid #fff", marginLeft: 10 }} />
            </div>
            <div style={{ fontSize: 34, fontWeight: 800, textShadow: "0 2px 8px rgba(0,0,0,.3)" }}>{item.t}</div>
            <div style={{ fontSize: 22, marginTop: 8, opacity: 0.9 }}>♥ {item.k}　·　@刷不停</div>
          </div>
        );
      })}
    </div>
  );
};

/** 0→1 的进场 */
export const useIn = (from: number, dur = 12) => {
  const frame = useCurrentFrame();
  return interpolate(frame, [from, from + dur], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
};
