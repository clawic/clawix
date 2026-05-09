// Mirror of WordWrapToggleIcon.swift in its resting (wrap) state. The Mac
// version morphs between wrap and no-wrap; here we expose `progress` as a
// 0..1 number too in case any caller wants the morph.
import type { IconProps } from "../lib/types";

interface Props extends IconProps {
  progress?: number;
  rightBarOpacity?: number;
}

export function WordWrapIcon({
  size = 14,
  color = "currentColor",
  strokeWidth,
  className,
  style,
  progress = 0,
  rightBarOpacity = 1,
}: Props) {
  const lw = strokeWidth ?? 1.0;
  const lerp = (a: number, b: number) => a + (b - a) * progress;
  const pt = (ax: number, ay: number, bx: number, by: number) =>
    `${lerp(ax, bx).toFixed(3)},${lerp(ay, by).toFixed(3)}`;
  const arrow =
    `M${pt(13, 5, 5, 12)} ` +
    `C${pt(14.1, 5, 7, 12)} ${pt(15, 5.9, 9, 12)} ${pt(15, 7, 11, 12)} ` +
    `L${pt(15, 11, 13, 12)} ` +
    `C${pt(15, 13.76, 14, 12)} ${pt(12.76, 16, 15, 12)} ${pt(10, 16, 16, 12)} ` +
    `L${pt(4, 16, 17, 12)} ` +
    `M${pt(8, 13, 13, 8)} L${pt(4, 16, 17, 12)} L${pt(8, 19, 13, 16)}`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth={lw}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={style}
    >
      <path d={arrow} />
      <path d="M20,5 L20,19" opacity={rightBarOpacity} />
    </svg>
  );
}
