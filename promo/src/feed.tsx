import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { FONT } from "./theme";

// 短视频 App 的竖屏界面：每条视频有自己会动的小画面，外面是点赞、评论、文案、进度条这些
// t：这条视频开始播了多少帧（每条都从 0 开始播）

const Cat = ({ t }: { t: number }) => {
  // 猫跳上桌子，没站稳，翻下去
  const jump = Math.min(1, t / 14);
  const fall = Math.max(0, (t - 18) / 12);
  const x = 120 + jump * 90 + fall * 40;
  const y = 330 - Math.sin(Math.PI * jump) * 120 - (jump >= 1 ? 70 : 0) + Math.pow(fall, 2) * 160;
  const rot = fall * 160;
  return (
    <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      <rect width="400" height="520" fill="#ffe7c7" />
      <rect x="0" y="400" width="400" height="120" fill="#e9b97a" />
      <rect x="200" y="300" width="170" height="16" rx="4" fill="#8a5a33" />
      <rect x="215" y="316" width="12" height="90" fill="#8a5a33" /><rect x="345" y="316" width="12" height="90" fill="#8a5a33" />
      <circle cx="320" cy="285" r="14" fill="#ff7b7b" />
      <g transform={`translate(${x} ${y}) rotate(${rot})`}>
        <ellipse cx="0" cy="0" rx="46" ry="30" fill="#f29b3d" />
        <circle cx="38" cy="-24" r="24" fill="#f29b3d" />
        <path d="M24 -42 L30 -64 L42 -46 Z M44 -46 L56 -62 L58 -40 Z" fill="#f29b3d" />
        <circle cx="46" cy="-26" r="4" fill="#222" /><circle cx="32" cy="-26" r="4" fill="#222" />
        <path d="M-44 -6 Q -76 -40 -60 -60" stroke="#f29b3d" strokeWidth="10" fill="none" strokeLinecap="round" />
      </g>
      {t > 26 && <text x="200" y="140" textAnchor="middle" fontSize="64" fontWeight="900" fill="#ff4d6d">翻车了！</text>}
    </svg>
  );
};

const Melon = ({ t }: { t: number }) => {
  const bites = Math.min(4, Math.floor(t / 8));
  return (
    <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      <rect width="400" height="520" fill="#d8f3dc" />
      <circle cx="200" cy="290" r="150" fill="#2d6a4f" />
      <circle cx="200" cy="290" r="138" fill="#ff5d73" />
      {[[150, 250], [230, 230], [180, 330], [260, 310], [140, 320]].map(([x, y], i) => <ellipse key={i} cx={x} cy={y} rx="6" ry="10" fill="#222" />)}
      {Array.from({ length: bites }, (_, i) => <circle key={i} cx={330 - i * 30} cy={170 + i * 10} r="46" fill="#d8f3dc" />)}
      <text x="200" y="90" textAnchor="middle" fontSize="54" fontWeight="900" fill="#1b4332">一口！</text>
    </svg>
  );
};

const Snow = ({ t }: { t: number }) => {
  const hop = Math.abs(Math.sin(t / 5)) * 30;
  return (
    <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      <rect width="400" height="520" fill="#a9c6e8" />
      <rect y="380" width="400" height="140" fill="#fff" />
      {Array.from({ length: 30 }, (_, i) => (
        <circle key={i} cx={(i * 53 + t * (1 + (i % 3))) % 400} cy={(i * 37 + t * (3 + (i % 4))) % 400} r={3 + (i % 3)} fill="#fff" />
      ))}
      <g transform={`translate(200 ${360 - hop})`}>
        <ellipse cx="0" cy="0" rx="60" ry="34" fill="#c08552" />
        <circle cx="54" cy="-30" r="30" fill="#c08552" />
        <ellipse cx="44" cy="-58" rx="12" ry="22" fill="#8d5524" transform="rotate(-20 44 -58)" />
        <circle cx="64" cy="-34" r="5" fill="#222" /><circle cx="82" cy="-24" r="7" fill="#222" />
        <path d="M-58 -10 Q -90 -30 -84 -56" stroke="#c08552" strokeWidth="12" fill="none" strokeLinecap="round"
          transform={`rotate(${Math.sin(t / 2) * 20} -58 -10)`} />
      </g>
    </svg>
  );
};

const Dance = ({ t }: { t: number }) => {
  const a = Math.sin(t / 3);
  return (
    <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      <rect width="400" height="520" fill="#2b2250" />
      {[0, 1, 2].map((i) => <circle key={i} cx={80 + i * 120} cy={80} r={40} fill={["#ff6fa8", "#6fd3ff", "#ffd84d"][i]} opacity={0.3 + 0.3 * Math.abs(Math.sin(t / 4 + i))} />)}
      <g transform={`translate(200 ${300 + Math.abs(a) * -16})`} stroke="#fff" strokeWidth="12" strokeLinecap="round" fill="none">
        <circle cx="0" cy="-110" r="26" fill="#fff" />
        <path d="M0 -84 L0 10" />
        <path d={`M0 -60 L${-60 * a} ${-110 + 30 * a}`} /><path d={`M0 -60 L${60 * a} ${-20 - 30 * a}`} />
        <path d={`M0 10 L${-40 - 20 * a} 90`} /><path d={`M0 10 L${40 - 20 * a} 90`} />
      </g>
    </svg>
  );
};

const Money = ({ t }: { t: number }) => {
  const n = Math.min(6, 1 + Math.floor(t / 6));
  return (
    <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      <rect width="400" height="520" fill="#fff4cc" />
      {Array.from({ length: n }, (_, i) => (
        <g key={i} transform={`translate(${70 + (i % 3) * 90} ${400 - Math.floor(i / 3) * 60})`}>
          <rect width="80" height="44" rx="6" fill="#4caf50" stroke="#2e7d32" strokeWidth="4" />
          <circle cx="40" cy="22" r="12" fill="#a5d6a7" />
        </g>
      ))}
      <path d={`M60 300 L170 230 L230 270 L340 150`} stroke="#e53935" strokeWidth="14" fill="none" strokeLinecap="round"
        strokeDasharray="500" strokeDashoffset={500 - Math.min(500, t * 22)} />
      <text x="200" y="110" textAnchor="middle" fontSize="60" fontWeight="900" fill="#e53935">月入十万？</text>
    </svg>
  );
};

const Twist = ({ t }: { t: number }) => (
  <svg viewBox="0 0 400 520" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
    <rect width="400" height="520" fill="#111" />
    <text x="200" y="300" textAnchor="middle" fontSize={140 + Math.sin(t / 2) * 12} fontWeight="900" fill={t % 8 < 4 ? "#ffd84d" : "#ff4d6d"}>？！</text>
    <text x="200" y="130" textAnchor="middle" fontSize="40" fontWeight="800" fill="#fff">后面还有……</text>
  </svg>
);

export const VIDEOS = [
  { Scene: Cat, user: "猫猫翻车日记", text: "主子今天也很努力 #猫 #萌宠", likes: "23.1万", comments: "8812", music: "原声 - 猫猫翻车日记" },
  { Scene: Melon, user: "大胃王小美", text: "挑战一口吃掉一整个西瓜 #吃播", likes: "8.1万", comments: "2301", music: "热门 BGM - 一口一口" },
  { Scene: Snow, user: "柯基豆豆", text: "狗狗第一次见到雪 #狗狗 #下雪了", likes: "45.6万", comments: "1.2万", music: "原声 - 柯基豆豆" },
  { Scene: Dance, user: "舞蹈区小王", text: "这个舞三秒学会 #手势舞 #挑战", likes: "12.8万", comments: "6543", music: "洗脑神曲 - 停不下来" },
  { Scene: Money, user: "财富密码", text: "三秒教你月入十万（真的） #副业", likes: "3.3万", comments: "9999+", music: "原声 - 财富密码" },
  { Scene: Twist, user: "反转大师", text: "这个转折我真的没想到 #剧情 #反转", likes: "67.0万", comments: "3.4万", music: "悬疑配乐 - 后面还有" },
];

const Heart = () => <svg width="54" height="50" viewBox="0 0 24 22"><path d="M12 21 C 4 14 0 10 0 6 A6 6 0 0 1 12 3 A6 6 0 0 1 24 6 C 24 10 20 14 12 21 Z" fill="#fff" /></svg>;
const Chat = () => <svg width="52" height="50" viewBox="0 0 24 22"><path d="M12 1 C 5 1 0 5 0 10 C 0 13 2 15.5 4 17 L 3 21 L 8 19 C 9 19.3 10.5 19.5 12 19.5 C 19 19.5 24 15 24 10 C 24 5 19 1 12 1 Z" fill="#fff" /></svg>;
const Star = () => <svg width="52" height="50" viewBox="0 0 24 23"><path d="M12 0 L15 8 L24 8.5 L17 14 L19.5 23 L12 18 L4.5 23 L7 14 L0 8.5 L9 8 Z" fill="#fff" /></svg>;
const Share = () => <svg width="50" height="46" viewBox="0 0 24 22"><path d="M14 0 L24 9 L14 18 L14 13 C 7 13 3 16 0 21 C 1 13 5 7 14 6 Z" fill="#fff" /></svg>;

/** 一条正在播的竖屏视频（含界面） */
const VideoCard = ({ i, t }: { i: number; t: number }) => {
  const v = VIDEOS[((i % VIDEOS.length) + VIDEOS.length) % VIDEOS.length];
  const icon = (node: React.ReactNode, label: string) => (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4, fontSize: 18, fontWeight: 700,
      filter: "drop-shadow(0 2px 3px rgba(0,0,0,.4))" }}>{node}{label}</div>
  );
  const marquee = -((t * 2) % 260);
  return (
    <div style={{ position: "absolute", inset: 0, background: "#000", color: "#fff", fontFamily: FONT, overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 0 }}><v.Scene t={Math.max(0, t)} /></div>
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(transparent 55%, rgba(0,0,0,.55))" }} />
      <div style={{ position: "absolute", top: 18, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 28, fontSize: 24, fontWeight: 800,
        textShadow: "0 1px 4px rgba(0,0,0,.5)" }}>
        <span style={{ opacity: 0.7 }}>关注</span><span style={{ borderBottom: "3px solid #fff", paddingBottom: 4 }}>推荐</span>
      </div>
      <div style={{ position: "absolute", right: 14, bottom: 150, display: "flex", flexDirection: "column", alignItems: "center", gap: 20 }}>
        <div style={{ width: 62, height: 62, borderRadius: 31, background: "#ffb347", border: "3px solid #fff", position: "relative" }}>
          <div style={{ position: "absolute", bottom: -12, left: 19, width: 22, height: 22, borderRadius: 11, background: "#ff2c55", fontSize: 18,
            fontWeight: 900, textAlign: "center", lineHeight: "21px" }}>+</div>
        </div>
        {icon(<Heart />, v.likes)}
        {icon(<Chat />, v.comments)}
        {icon(<Star />, "收藏")}
        {icon(<Share />, "分享")}
      </div>
      <div style={{ position: "absolute", left: 20, right: 100, bottom: 46, textShadow: "0 1px 4px rgba(0,0,0,.6)" }}>
        <div style={{ fontSize: 26, fontWeight: 800 }}>@{v.user}</div>
        <div style={{ fontSize: 22, marginTop: 6, lineHeight: 1.4 }}>{v.text}</div>
        <div style={{ fontSize: 19, marginTop: 8, width: 240, overflow: "hidden", whiteSpace: "nowrap" }}>
          <span style={{ display: "inline-block", transform: `translateX(${marquee}px)` }}>♫ {v.music}　　♫ {v.music}</span>
        </div>
      </div>
      <div style={{ position: "absolute", left: 0, bottom: 0, height: 5, width: `${Math.min(100, (t / 90) * 100)}%`, background: "rgba(255,255,255,.85)" }} />
    </div>
  );
};

/** 竖屏视频流：swipes 是每次往上划的帧号（升序）；划的那一下有一点动态模糊 */
export const ShortVideoFeed = ({ swipes, start = 0 }: { swipes: number[]; start?: number }) => {
  const frame = useCurrentFrame();
  const done = swipes.filter((f) => f <= frame);
  const n = done.length;
  const last = done[n - 1] ?? -999;
  const p = interpolate(frame - last, [0, 7], [0, 1], { extrapolateRight: "clamp", easing: (x) => 1 - Math.pow(1 - x, 3) });
  const moving = n > 0 && p < 1;
  const cur = start + n;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", filter: moving ? "blur(1.5px)" : undefined }}>
      {moving && <div style={{ position: "absolute", inset: 0, transform: `translateY(${-p * 100}%)` }}><VideoCard i={cur - 1} t={frame - (done[n - 2] ?? 0)} /></div>}
      <div style={{ position: "absolute", inset: 0, transform: `translateY(${moving ? (1 - p) * 100 : 0}%)` }}><VideoCard i={cur} t={frame - last} /></div>
    </div>
  );
};
