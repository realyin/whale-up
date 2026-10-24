import { Img, staticFile, useCurrentFrame } from "remotion";

// 角色包里的图：表情图都是 915×750 同一画布，尾巴单独一张叠在后面摆；pose-* 是自带尾巴的整张姿势图
const BASE = { w: 915, h: 750 };
const SIZES: Record<string, [number, number]> = {
  "pose-dance1": [887, 812], "pose-dance2": [887, 812], "pose-eat_sit1": [853, 793], "pose-eat_sit2": [853, 793],
  "pose-heart": [819, 770], "pose-milktea": [912, 789], "pose-read": [936, 711], "pose-sleep_curl": [816, 754],
  "pose-stretch_stand": [710, 801], "pose-swim1": [940, 727], "pose-swim2": [940, 727], "pose-work": [916, 627],
};
const TAIL = { at: [695, 315], pivot: [6, 230], w: 220, h: 285 };

export type WhaleProps = {
  pose: string;
  /** 脚底中心在画面上的位置 */
  x: number;
  y: number;
  /** 表情图画布的高度（像素），姿势图按同样比例缩放 */
  height?: number;
  rotate?: number;
  scaleX?: number;
  scaleY?: number;
  opacity?: number;
  flip?: boolean;
};

export const Whale = ({ pose, x, y, height = 320, rotate = 0, scaleX = 1, scaleY = 1, opacity = 1, flip }: WhaleProps) => {
  const frame = useCurrentFrame();
  const s = height / BASE.h;
  const [w, h] = SIZES[pose] ?? [BASE.w, BASE.h];
  const breathe = 1 + 0.018 * Math.sin(frame / 9);
  const tailRot = 6 * Math.sin((frame / 30) * ((2 * Math.PI) / 2.6));
  const ownPose = pose.startsWith("pose-");
  return (
    <div style={{
      position: "absolute", left: x - (w * s) / 2, top: y - h * s, width: w * s, height: h * s, opacity,
      transformOrigin: "50% 100%",
      transform: `rotate(${rotate}deg) scale(${(flip ? -1 : 1) * scaleX * (1 + (breathe - 1) * 0.3)}, ${scaleY * breathe})`,
    }}>
      {!ownPose && (
        <Img src={staticFile("whale/tail.png")} style={{
          position: "absolute", left: TAIL.at[0] * s, top: TAIL.at[1] * s, width: TAIL.w * s, height: TAIL.h * s,
          transformOrigin: `${TAIL.pivot[0] * s}px ${TAIL.pivot[1] * s}px`, transform: `rotate(${tailRot}deg)`,
        }} />
      )}
      <Img src={staticFile(`whale/${pose}.png`)} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
    </div>
  );
};
