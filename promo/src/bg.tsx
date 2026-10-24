import { random, staticFile, useCurrentFrame } from "remotion";

/** 深夜：藏青夜空、弯月、星星、远处城市灯光、近处楼的剪影 */
export const NightBg = () => {
  const frame = useCurrentFrame();
  const stars = Array.from({ length: 90 }, (_, i) => {
    const r = (k: string) => random(`star-${i}-${k}`);
    const tw = 0.5 + 0.5 * Math.sin(frame / (10 + r("p") * 20) + r("o") * 6);
    return <circle key={i} cx={r("x") * 1920} cy={r("y") * 620} r={1 + r("s") * 2.2} fill="#fff" opacity={0.3 + 0.6 * tw} />;
  });
  // 两排楼：远处浅一点、近处深一点，窗户随机亮
  const buildings = (row: number, base: number, color: string, winColor: string) => {
    const out = [];
    let x = -20;
    let i = 0;
    while (x < 1940) {
      const r = (k: string) => random(`b${row}-${i}-${k}`);
      const w = 70 + r("w") * 110;
      const h = (row ? 160 : 260) + r("h") * (row ? 160 : 220);
      out.push(<rect key={`b${i}`} x={x} y={base - h} width={w} height={h + 40} fill={color} />);
      for (let wy = base - h + 18; wy < base - 10; wy += 26) {
        for (let wx = x + 12; wx < x + w - 14; wx += 22) {
          const lit = random(`w${row}-${i}-${wx}-${wy}`) < (row ? 0.22 : 0.3);
          if (lit) out.push(<rect key={`w${i}-${wx}-${wy}`} x={wx} y={wy} width={9} height={13} rx={1.5} fill={winColor}
            opacity={0.55 + 0.45 * random(`l${row}-${wx}-${wy}`)} />);
        }
      }
      x += w + 6;
      i++;
    }
    return out;
  };
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#0b1233" />
          <stop offset="0.6" stopColor="#1d2a5e" />
          <stop offset="0.85" stopColor="#4a4a8a" />
          <stop offset="1" stopColor="#7b6bb0" />
        </linearGradient>
        <radialGradient id="glow">
          <stop offset="0" stopColor="#fff6d8" stopOpacity="0.5" />
          <stop offset="1" stopColor="#fff6d8" stopOpacity="0" />
        </radialGradient>
      </defs>
      <rect width={1920} height={1080} fill="url(#sky)" />
      {stars}
      <circle cx={1600} cy={190} r={150} fill="url(#glow)" />
      <circle cx={1600} cy={190} r={62} fill="#fff4c9" />
      <circle cx={1628} cy={170} r={58} fill="#1a2557" />
      {buildings(1, 900, "#2a2f6a", "#ffe6a0")}
      {buildings(0, 1080, "#141838", "#ffd27a")}
    </svg>
  );
};

/** 白天：浅蓝天空、蓬松的云、远处海面，海里露出一条小鲸鱼尾巴 */
export const DayBg = () => {
  const frame = useCurrentFrame();
  const cloud = (cx: number, cy: number, s: number, speed: number, key: string) => {
    const x = ((cx + frame * speed) % 2300) - 200;
    return (
      <g key={key} transform={`translate(${x} ${cy}) scale(${s})`} opacity={0.95}>
        <ellipse cx={0} cy={20} rx={120} ry={38} fill="#fff" />
        <circle cx={-50} cy={0} r={46} fill="#fff" />
        <circle cx={10} cy={-22} r={60} fill="#fff" />
        <circle cx={70} cy={4} r={42} fill="#fff" />
      </g>
    );
  };
  const bob = Math.sin(frame / 14) * 6;
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <defs>
        <linearGradient id="dsky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7db7f5" />
          <stop offset="0.75" stopColor="#cfe6ff" />
          <stop offset="1" stopColor="#fff6e0" />
        </linearGradient>
        <linearGradient id="sea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#5d9be8" />
          <stop offset="1" stopColor="#2f6fc9" />
        </linearGradient>
      </defs>
      <rect width={1920} height={1080} fill="url(#dsky)" />
      {cloud(200, 170, 1.1, 0.6, "c1")}
      {cloud(900, 120, 0.8, 0.4, "c2")}
      {cloud(1500, 260, 1.3, 0.7, "c3")}
      {cloud(600, 380, 0.7, 0.5, "c4")}
      <rect y={860} width={1920} height={220} fill="url(#sea)" />
      {[0, 1, 2, 3].map((i) => (
        <path key={i} d={`M0 ${880 + i * 45} Q 240 ${870 + i * 45 + Math.sin(frame / 12 + i) * 6} 480 ${880 + i * 45} T 960 ${880 + i * 45} T 1440 ${880 + i * 45} T 1920 ${880 + i * 45}`}
          stroke="#ffffff" strokeOpacity={0.35} strokeWidth={4} fill="none" />
      ))}
      <image href={staticFile("whale/tail.png")} x={1500} y={712 + bob} width={150} height={194} />
      <rect x={1440} y={880} width={270} height={30} fill="url(#sea)" />
      <path d={`M1470 ${886 + bob / 2} q 30 -18 60 0 t 60 0 t 60 0 t 60 0`} stroke="#ffffff" strokeOpacity={0.8} strokeWidth={5} fill="none" />
      <circle cx={1490} cy={850 + bob} r={7} fill="#fff" opacity={0.85} />
      <circle cx={1670} cy={835 + bob} r={6} fill="#fff" opacity={0.85} />
    </svg>
  );
};
