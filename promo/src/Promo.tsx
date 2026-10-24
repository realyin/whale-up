import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { DayBg, NightBg } from "./bg";
import { C, FONT, ROUND } from "./theme";
import { Bubble, Browser, Cursor, Feed, MenuBar, Stars, Subtitle, useIn } from "./ui";
import { Whale } from "./Whale";

// 时间线（30fps）：每段的起点和长度按配音时长排
const S = {
  night: [0, 150], peek: [150, 120], no: [270, 90], magic: [360, 210], title: [570, 135],
  ring: [705, 117], stats: [822, 120], ai: [942, 132], digest: [1074, 123], force: [1197, 147],
  eat: [1344, 108], stretch: [1452, 45], swim: [1497, 45], dance: [1542, 123], bye: [1665, 160],
} as const;
export const TOTAL = 1825;

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const Voice = ({ id, at }: { id: string; at: number }) => (
  <Sequence from={at} layout="none"><Audio src={staticFile(`voice/${id}.mp3`)} /></Sequence>
);

// ---------- 1–4：深夜刷视频，被她施法关掉 ----------

const BROWSER = { x: 330, y: 110, w: 1180, h: 740 };
const HOME = { x: 1690, y: 1050 };

const NightScene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame; // 这一段从 0 开始
  // 刷到第几个
  const count = Math.min(47, 40 + Math.floor(local / 22));

  // 她：第 2 段从屏幕下面冒出来；第 4 段飞去浏览器右上角施法，再飞回来
  const peekFrom = S.peek[0] + 10;
  const rise = spring({ frame: local - peekFrom, fps, config: { damping: 12, stiffness: 120 } });
  const flyStart = S.magic[0];
  const fly = spring({ frame: local - flyStart, fps, config: { damping: 14, stiffness: 90 } });
  const back = spring({ frame: local - (S.magic[0] + 150), fps, config: { damping: 14, stiffness: 90 } });
  const target = { x: BROWSER.x + BROWSER.w + 60, y: BROWSER.y + 470 };
  const wx = HOME.x + (target.x - HOME.x) * (fly - back);
  const wy = HOME.y + 300 * (1 - rise) + (target.y - HOME.y) * (fly - back) - Math.sin(Math.PI * Math.min(1, fly)) * 120 * (1 - back);
  const castAt = S.magic[0] + 30;
  const closeAt = S.magic[0] + 100;
  const pose = local >= castAt && local < castAt + 60 ? "cast"
    : local >= S.no[0] + 15 && local < closeAt ? "angry"
    : local >= closeAt ? "idle" : "watching";

  // 浏览器“砰”地关掉
  const poof = interpolate(local, [closeAt, closeAt + 8], [1, 0], clamp);
  const cursorIn = interpolate(local, [S.no[0], S.no[0] + 14], [0, 1], clamp);
  const pressed = local >= S.no[0] + 14 && local < S.no[0] + 20;
  const btn = { x: HOME.x - 120, y: HOME.y - 420 };

  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <NightBg />
      <MenuBar time="02:13" />
      {poof > 0 && (
        <Browser {...BROWSER} title="刷刷看 - 停不下来" url="https://shuashuakan.example/feed"
          style={{ transform: `scale(${0.6 + 0.4 * poof})`, opacity: poof }}>
          <div style={{ position: "absolute", inset: 0, background: "#0d0f16" }} />
          <div style={{ position: "absolute", left: "50%", top: 24, bottom: 24, width: 420, marginLeft: -210, borderRadius: 16, overflow: "hidden" }}>
            <Feed />
          </div>
          <div style={{ position: "absolute", right: 36, top: 30, color: "#fff", fontSize: 26, fontWeight: 800,
            background: "rgba(255,255,255,.12)", padding: "8px 18px", borderRadius: 12 }}>第 {count} 个</div>
        </Browser>
      )}
      {local >= closeAt && local < closeAt + 50 && (
        <div style={{ position: "absolute", left: BROWSER.x + BROWSER.w / 2 - 120, top: BROWSER.y + BROWSER.h / 2 - 80,
          fontSize: 120, fontWeight: 900, color: "#fff", transform: `scale(${interpolate(local, [closeAt, closeAt + 10], [0.3, 1.2], clamp)})`,
          opacity: interpolate(local, [closeAt + 25, closeAt + 50], [1, 0], clamp), textShadow: `0 0 0 ${C.ink}, 6px 6px 0 ${C.pink}` }}>砰！</div>
      )}

      <Whale pose={pose} x={wx} y={wy} height={300} />
      {pose === "angry" && local < castAt && <AngerMark x={wx - 40} y={wy - 300} />}
      {local >= castAt + 10 && <Stars x={wx - 120} y={wy - 190} from={castAt + 10} dx={-1} dy={-0.25} seed="cast" count={160} spread={50} />}
      {local >= closeAt && <Stars x={BROWSER.x + BROWSER.w / 2} y={BROWSER.y + BROWSER.h / 2} from={closeAt} burst count={110} seed="burst" />}

      {/* 气泡和按钮 */}
      {local >= peekFrom + 12 && local < S.no[0] + 15 && (
        <>
          <Bubble text="……你已经刷了 47 分钟了哦。" x={HOME.x - 160} y={HOME.y - 330} width={480} from={peekFrom + 12} />
          <div style={{ position: "absolute", left: btn.x - 230, top: btn.y + 170, display: "flex", gap: 14,
            opacity: interpolate(local, [peekFrom + 40, peekFrom + 50], [0, 1], clamp) }}>
            <div style={{ background: C.accent, color: "#fff", fontWeight: 800, fontSize: 26, padding: "10px 22px", borderRadius: 30,
              border: `3px solid ${C.ink}`, boxShadow: `0 4px 0 ${C.ink}` }}>好，关掉它</div>
            <div style={{ background: C.paper, color: C.ink, fontWeight: 800, fontSize: 26, padding: "10px 22px", borderRadius: 30,
              border: `3px solid ${C.ink}`, boxShadow: pressed ? "none" : `0 4px 0 ${C.ink}`, transform: pressed ? "translateY(4px)" : "none" }}>再刷 5 分钟</div>
          </div>
        </>
      )}
      {local >= S.no[0] + 15 && local < castAt && <Bubble text="不——行！" x={HOME.x - 140} y={HOME.y - 330} width={300} from={S.no[0] + 15} />}
      {local >= castAt - 5 && local < closeAt && <Bubble text="看我的魔法！" x={wx - 40} y={wy - 330} width={340} from={castAt - 5} />}
      {local >= closeAt + 20 && <Bubble text="搞定！关掉啦～" x={HOME.x - 140} y={HOME.y - 330} width={360} from={closeAt + 20} />}

      {cursorIn > 0 && local < S.no[0] + 40 && (
        <Cursor x={interpolate(cursorIn, [0, 1], [1100, btn.x + 60])} y={interpolate(cursorIn, [0, 1], [700, btn.y + 190])} pressed={pressed} />
      )}
      {local < S.peek[0] && <Subtitle text="凌晨两点。你：“再刷最后一个。”" />}
    </AbsoluteFill>
  );
};

/** 漫画里的生气符号 */
const AngerMark = ({ x, y }: { x: number; y: number }) => {
  const frame = useCurrentFrame();
  const s = 1 + 0.12 * Math.sin(frame / 3);
  return (
    <svg width={90} height={90} viewBox="-45 -45 90 90" style={{ position: "absolute", left: x, top: y, transform: `scale(${s})` }}>
      {[0, 90, 180, 270].map((a) => (
        <path key={a} d="M 8 -30 Q 8 -8 30 -8" stroke="#ff3b5c" strokeWidth={9} fill="none" strokeLinecap="round" transform={`rotate(${a})`} />
      ))}
    </svg>
  );
};

// ---------- 5：标题 ----------

const Logo = ({ size = 220 }: { size?: number }) => (
  <div style={{ fontFamily: ROUND, fontSize: size, fontWeight: 700, color: C.paper, letterSpacing: size * 0.06, lineHeight: 1.1,
    WebkitTextStroke: `${size * 0.09}px ${C.ink}`, paintOrder: "stroke fill",
    filter: `drop-shadow(0 ${size * 0.04}px 0 ${C.ink})` }}>
    鲸<span style={{ color: "#9cc0f0" }}>醒</span>
  </div>
);

const TitleScene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: frame - 4, fps, config: { damping: 9, stiffness: 140 } });
  const sub = useIn(22, 14);
  return (
    <AbsoluteFill>
      <DayBg />
      <div style={{ position: "absolute", left: 0, right: 0, top: 230, display: "flex", flexDirection: "column", alignItems: "center",
        transform: `scale(${pop})` }}>
        <Logo />
        <div style={{ marginTop: 34, fontFamily: ROUND, fontSize: 58, fontWeight: 700, color: C.ink, opacity: sub,
          background: C.paper, border: `4px solid ${C.ink}`, borderRadius: 60, padding: "12px 44px", boxShadow: `0 6px 0 ${C.ink}` }}>
          会施魔法的上网小助手
        </div>
      </div>
      <Whale pose="idle" x={1530 + (1 - sub) * 400} y={1000} height={340} />
      <Stars x={960} y={360} from={4} burst count={60} seed="title" />
    </AbsoluteFill>
  );
};

// ---------- 6：功能 ----------

const FeatureFrame = ({ n, title, children, pose, line, voiceAt = 8 }:
  { n: string; title: string; children: React.ReactNode; pose?: string; line: string; voiceAt?: number }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 14, stiffness: 150 } });
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <DayBg />
      <div style={{ position: "absolute", left: 90, top: 70, display: "flex", alignItems: "center", gap: 22, transform: `translateX(${(1 - enter) * -300}px)` }}>
        <div style={{ background: C.ink, color: C.paper, fontSize: 44, fontWeight: 900, borderRadius: 18, padding: "6px 20px" }}>{n}</div>
        <div style={{ fontFamily: ROUND, fontSize: 70, fontWeight: 700, color: C.ink, WebkitTextStroke: `12px ${C.paper}`, paintOrder: "stroke fill" }}>{title}</div>
      </div>
      <div style={{ position: "absolute", left: 90, top: 200, width: 1150, height: 720, transform: `translateY(${(1 - enter) * 60}px)`, opacity: enter }}>
        {children}
      </div>
      {pose && <Whale pose={pose} x={1580} y={1020} height={420} />}
      <Bubble text={line} x={1560} y={pose ? 580 : 330} width={520} from={voiceAt} />
    </AbsoluteFill>
  );
};

const Card = ({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) => (
  <div style={{ background: C.paper, border: `4px solid ${C.ink}`, borderRadius: 28, boxShadow: `0 8px 0 ${C.ink}`, padding: 36, position: "relative", ...style }}>
    {children}
  </div>
);

const RING = [["actions", "动作"], ["cast", "施魔法"], ["today", "今天"], ["lists", "加入名单"], ["pause", "暂停 1 小时"], ["more", "更多"]];
const RingScene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const cx = 640, cy = 400, r = 320;
  return (
    <FeatureFrame n="01" title="右键点她，功能围一圈" line="右键点我，功能都围着我转一圈！" voiceAt={8}>
      <Whale pose="idle" x={cx} y={cy + 140} height={300} />
      {RING.map(([id, label], i) => {
        const p = spring({ frame: frame - 14 - i * 4, fps, config: { damping: 10, stiffness: 160 } });
        const a = -Math.PI / 2 + (i * 2 * Math.PI) / RING.length;
        const x = cx + Math.cos(a) * r * p, y = cy + Math.sin(a) * r * 0.8 * p;
        return (
          <div key={id} style={{ position: "absolute", left: x - 62, top: y - 62, width: 124, height: 124, transform: `scale(${p})` }}>
            <div style={{ width: 124, height: 124, borderRadius: 70, background: C.paper, border: `4px solid ${C.ink}`, boxShadow: `0 5px 0 ${C.ink}`,
              display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Img src={staticFile(`whale/icons/${id}.png`)} style={{ width: 100, height: 100 }} />
            </div>
            <div style={{ position: "absolute", top: 118, left: "50%", transform: "translateX(-50%)", whiteSpace: "nowrap", background: C.ink,
              color: C.paper, fontSize: 24, fontWeight: 800, padding: "2px 12px 4px", borderRadius: 10 }}>{label}</div>
          </div>
        );
      })}
    </FeatureFrame>
  );
};

const StatsScene = () => {
  const frame = useCurrentFrame();
  const rows: [string, number, boolean][] = [["刷刷看", 47, true], ["学习 Swift", 38, false], ["猫猫视频站", 22, true], ["技术文档", 15, false]];
  return (
    <FeatureFrame n="02" title="你每天刷了多久，记得清清楚楚" pose="watching" line="你每天刷了多久，我都偷偷记着呢。">
      <Card style={{ width: 1120 }}>
        <div style={{ fontFamily: ROUND, fontSize: 44, fontWeight: 700, color: C.ink, marginBottom: 26 }}>今天</div>
        {rows.map(([name, min, junk], i) => {
          const g = interpolate(frame, [10 + i * 6, 40 + i * 6], [0, 1], clamp);
          return (
            <div key={name} style={{ display: "flex", alignItems: "center", gap: 22, margin: "26px 0" }}>
              <div style={{ width: 230, fontSize: 38, fontWeight: 700, color: C.ink }}>{name}</div>
              <div style={{ height: 52, width: min * 12 * g, borderRadius: 14, background: junk ? C.junk : C.good }} />
              <div style={{ fontSize: 36, fontWeight: 800, color: junk ? C.junk : C.good, whiteSpace: "nowrap" }}>{Math.round(min * g)} 分钟</div>
            </div>
          );
        })}
        <div style={{ marginTop: 28, display: "flex", gap: 30, fontSize: 30, color: "#5a6383", fontWeight: 700 }}>
          <span><b style={{ color: C.junk }}>■</b> 没营养</span><span><b style={{ color: C.good }}>■</b> 有营养</span>
        </div>
      </Card>
    </FeatureFrame>
  );
};

const AiScene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const item = (title: string, good: boolean, at: number) => {
    const slide = spring({ frame: frame - at, fps, config: { damping: 14 } });
    const stamp = spring({ frame: frame - at - 18, fps, config: { damping: 8, stiffness: 200 } });
    return (
      <Card style={{ width: 1120, marginBottom: 50, transform: `translateX(${(1 - slide) * -600}px)` }}>
        <div style={{ display: "flex", alignItems: "center", gap: 30, paddingRight: 260 }}>
          <div style={{ width: 210, height: 124, flexShrink: 0, borderRadius: 16, background: good ? "linear-gradient(135deg,#89f7fe,#66a6ff)" : "linear-gradient(135deg,#ff9a8b,#ff6a88)" }} />
          <div style={{ fontSize: 40, fontWeight: 800, color: C.ink, lineHeight: 1.35 }}>{title}</div>
        </div>
        <div style={{ position: "absolute", right: 34, top: "50%", marginTop: -40, transform: `rotate(-12deg) scale(${frame >= at + 18 ? 2.2 - 1.2 * stamp : 0})`,
          border: `7px solid ${good ? C.good : C.junk}`, color: good ? C.good : C.junk, fontFamily: ROUND, fontSize: 48, fontWeight: 700, padding: "4px 20px", borderRadius: 16,
          background: "rgba(255,255,255,.92)" }}>{good ? "有营养 ✓" : "没营养 ✗"}</div>
      </Card>
    );
  };
  return (
    <FeatureFrame n="03" title="AI 判断：有没有营养" pose="pose-read" line="学习的放你一马，没营养的……哼哼。">
      <div style={{ paddingTop: 40 }}>
        {item("Swift 并发编程，30 分钟讲清楚", true, 6)}
        {item("猫猫翻车合集 第 47 集", false, 40)}
      </div>
    </FeatureFrame>
  );
};

const DIGEST = "今天没营养 47 分钟，比昨天少 12 分钟。凌晨 1 点以后刷得最多——那会儿你不是想放松，是不想睡。明天 12 点前躺下，好不好？";
const DigestScene = () => {
  const frame = useCurrentFrame();
  const shown = Math.floor(interpolate(frame, [10, 100], [0, DIGEST.length], clamp));
  return (
    <FeatureFrame n="04" title="每天给你写一份小结" pose="pose-work" line="每天晚上，我还会给你写一份小结。">
      <Card style={{ width: 1120, minHeight: 470 }}>
        <div style={{ fontSize: 30, fontWeight: 900, color: C.accent, marginBottom: 20, display: "flex", alignItems: "center", gap: 12 }}>
          <Img src={staticFile("whale/icons/today.png")} style={{ width: 56, height: 56 }} />今天的小结</div>
        <div style={{ fontSize: 46, lineHeight: 1.7, color: C.ink, fontWeight: 600, fontFamily: `"Songti SC", serif` }}>
          {DIGEST.slice(0, shown)}<span style={{ opacity: frame % 20 < 10 ? 1 : 0 }}>▍</span>
        </div>
      </Card>
    </FeatureFrame>
  );
};

const ForceScene = () => {
  const frame = useCurrentFrame();
  // 一打开就被关：反复三次
  const tries = [10, 45, 80];
  const k = tries.filter((t) => frame >= t).length;
  const last = tries[Math.max(0, k - 1)];
  const open = k > 0 && frame - last < 22;
  const scale = open ? interpolate(frame - last, [0, 6, 16, 22], [0.7, 1, 1, 0], clamp) : 0;
  return (
    <FeatureFrame n="05" title="强制关闭：刷够了，今天就别开了" pose="angry" line="今天刷够了？那就关掉，今天不许再开！">
      <div style={{ position: "relative", width: 1100, height: 640 }}>
        {scale > 0 && (
          <Browser x={40} y={20} w={1020} h={560} title="刷刷看" url="https://shuashuakan.example" style={{ transform: `scale(${scale})` }}>
            <Feed offset={frame} />
          </Browser>
        )}
        {k > 0 && !open && (
          <Card style={{ position: "absolute", left: 230, top: 120, width: 640, textAlign: "center" }}>
            <Img src={staticFile("whale/icons/sensitive.png")} style={{ width: 120, height: 120 }} />
            <div style={{ fontFamily: ROUND, fontSize: 46, fontWeight: 700, color: C.ink, marginTop: 8 }}>今天的 30 分钟用完啦</div>
          </Card>
        )}
        {k > 0 && (
          <div style={{ position: "absolute", left: 40, bottom: -40, fontSize: 40, fontWeight: 800, color: C.junk,
            background: C.paper, border: `3px solid ${C.junk}`, borderRadius: 16, padding: "6px 20px" }}>第 {k} 次打开 → 关掉</div>
        )}
      </div>
    </FeatureFrame>
  );
};

// ---------- 7：小动作串烧 ----------

const Montage = ({ title, children }: { title: string; children: React.ReactNode }) => (
  <AbsoluteFill style={{ fontFamily: FONT }}>
    <DayBg />
    {children}
    <div style={{ position: "absolute", left: 90, top: 70, fontFamily: ROUND, fontSize: 70, fontWeight: 700, color: C.ink, WebkitTextStroke: `12px ${C.paper}`, paintOrder: "stroke fill" }}>{title}</div>
  </AbsoluteFill>
);

const EatScene = () => {
  const frame = useCurrentFrame();
  const f = Math.floor(frame / 12) % 2 ? "pose-eat_sit2" : "pose-eat_sit1";
  const bob = -6 * Math.max(0, Math.sin((frame / 30) * Math.PI * 2.4));
  return (
    <Montage title="饭点到了，提醒你吃饭">
      <Whale pose={f} x={960} y={1000 + bob} height={560} />
      <Bubble text="开饭啦！大米饭最好吃了～" x={1300} y={420} width={480} from={6} />
    </Montage>
  );
};
const StretchScene = () => {
  const frame = useCurrentFrame();
  const s = 1 + 0.07 * Math.sin(Math.PI * Math.min(1, frame / 40));
  return (
    <Montage title="坐久了，伸个懒腰">
      <Whale pose="pose-stretch_stand" x={960} y={1000} height={560} scaleY={s} scaleX={2 - s} />
    </Montage>
  );
};
const SwimScene = () => {
  const frame = useCurrentFrame();
  const x = interpolate(frame, [0, 45], [-300, 2200]);
  const f = Math.floor(frame / 8) % 2 ? "pose-swim2" : "pose-swim1";
  return (
    <Montage title="无聊了，在屏幕里游个泳">
      <Whale pose={f} x={x} y={820 + Math.sin(frame / 6) * 30} height={420} flip rotate={Math.cos(frame / 6) * 4} />
    </Montage>
  );
};
const DanceScene = () => {
  const frame = useCurrentFrame();
  const beat = Math.abs(Math.sin((Math.PI * 2.2 * frame) / 30));
  const f = Math.floor((frame / 30) * 2.2) % 2 ? "pose-dance2" : "pose-dance1";
  return (
    <Montage title="还会陪你跳舞">
      <Whale pose={f} x={900} y={1010 - beat * 30} height={560} rotate={Math.sin((Math.PI * 2.2 * frame) / 30) * 5} />
      {[0, 1, 2, 3, 4].map((i) => {
        const t = (frame + i * 18) % 60;
        return <div key={i} style={{ position: "absolute", left: 760 + i * 90, top: 420 - t * 4, fontSize: 60, color: i % 2 ? C.pink : C.accent,
          opacity: 1 - t / 60, fontWeight: 900 }}>{i % 2 ? "♪" : "♫"}</div>;
      })}
      <Bubble text="陪你一起摸鱼……啊不是，一起努力！" x={1380} y={430} width={520} from={6} />
    </Montage>
  );
};

// ---------- 8：结尾 ----------

const ByeScene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const logo = spring({ frame: frame - 70, fps, config: { damping: 10, stiffness: 120 } });
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <DayBg />
      {Array.from({ length: 10 }, (_, i) => {
        const t = (frame + i * 13) % 90;
        return <div key={i} style={{ position: "absolute", left: 160 + ((i * 97) % 640), top: 760 - t * 6, fontSize: 40 + (i % 3) * 16,
          color: i % 2 ? "#ff6fa8" : "#ff8fb3", opacity: 1 - t / 90 }}>❤</div>;
      })}
      <Whale pose="pose-heart" x={960 - logo * 420} y={1010} height={520} />
      <Bubble text="少刷一点，多陪陪自己～" x={960 - logo * 420} y={500} width={460} from={8} />
      <div style={{ position: "absolute", left: 980, top: 300, transform: `scale(${logo})`, transformOrigin: "0 50%", display: "flex", flexDirection: "column", gap: 30 }}>
        <Logo size={200} />
        <div style={{ fontFamily: ROUND, fontSize: 56, fontWeight: 700, color: C.ink }}>别刷啦，鲸鲸盯着你哦</div>
        <div style={{ fontSize: 34, fontWeight: 700, color: "#4b5a8a" }}>macOS 菜单栏小助手 + Chrome 扩展</div>
      </div>
    </AbsoluteFill>
  );
};

// ---------- 总装 ----------

const at = (k: keyof typeof S) => S[k][0];
const len = (k: keyof typeof S) => S[k][1];

export const Promo = () => (
  <AbsoluteFill style={{ background: "#000" }}>
    <Sequence durationInFrames={at("title")}><NightScene /></Sequence>
    <Sequence from={at("title")} durationInFrames={len("title")}><TitleScene /></Sequence>
    <Sequence from={at("ring")} durationInFrames={len("ring")}><RingScene /></Sequence>
    <Sequence from={at("stats")} durationInFrames={len("stats")}><StatsScene /></Sequence>
    <Sequence from={at("ai")} durationInFrames={len("ai")}><AiScene /></Sequence>
    <Sequence from={at("digest")} durationInFrames={len("digest")}><DigestScene /></Sequence>
    <Sequence from={at("force")} durationInFrames={len("force")}><ForceScene /></Sequence>
    <Sequence from={at("eat")} durationInFrames={len("eat")}><EatScene /></Sequence>
    <Sequence from={at("stretch")} durationInFrames={len("stretch")}><StretchScene /></Sequence>
    <Sequence from={at("swim")} durationInFrames={len("swim")}><SwimScene /></Sequence>
    <Sequence from={at("dance")} durationInFrames={len("dance")}><DanceScene /></Sequence>
    <Sequence from={at("bye")} durationInFrames={len("bye")}><ByeScene /></Sequence>

    {/* 音效 */}
    {[at("peek") + 10, at("peek") + 22, at("no") + 15, at("magic") + 25, at("magic") + 120, at("title") + 4,
      ...[0, 1, 2, 3, 4, 5].map((i) => at("ring") + 14 + i * 4), at("stats"), at("ai") + 24, at("ai") + 58, at("digest"), at("force") + 10,
      at("force") + 45, at("force") + 80, at("eat") + 6, at("dance") + 6, at("bye") + 8, at("bye") + 70].map((f, i) => (
      <Sequence key={`pop${i}`} from={f} layout="none"><Audio src={staticFile("sfx/pop.mp3")} volume={0.35} /></Sequence>
    ))}
    <Sequence from={at("magic") + 38} layout="none"><Audio src={staticFile("sfx/sparkle.mp3")} volume={0.6} /></Sequence>
    <Sequence from={at("magic") + 60} layout="none"><Audio src={staticFile("sfx/sparkle.mp3")} volume={0.5} /></Sequence>
    <Sequence from={at("magic") + 100} layout="none"><Audio src={staticFile("sfx/boom.mp3")} volume={0.8} /></Sequence>
    <Sequence from={at("title") + 4} layout="none"><Audio src={staticFile("sfx/sparkle.mp3")} volume={0.5} /></Sequence>

    <Voice id="stare" at={at("peek") + 22} />
    <Voice id="no" at={at("no") + 15} />
    <Voice id="magic" at={at("magic") + 25} />
    <Voice id="done" at={at("magic") + 120} />
    <Voice id="title" at={at("title") + 8} />
    <Voice id="ring" at={at("ring") + 8} />
    <Voice id="stats" at={at("stats") + 8} />
    <Voice id="ai" at={at("ai") + 8} />
    <Voice id="digest" at={at("digest") + 8} />
    <Voice id="force" at={at("force") + 8} />
    <Voice id="eat" at={at("eat") + 6} />
    <Voice id="dance" at={at("dance") + 6} />
    <Voice id="bye" at={at("bye") + 8} />
  </AbsoluteFill>
);
