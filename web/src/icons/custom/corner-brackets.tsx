// Mirror of CornerBracketsIcon.swift: two diagonal corner brackets that
// morph between collapsed and expanded states.
import type { IconProps } from "../lib/types";

interface Props extends IconProps {
  variant?: "collapsed" | "expanded";
}

type V2 = readonly [number, number];

function corner(s: V2, v: V2, e: V2, r: number): string {
  const sv: V2 = [v[0] - s[0], v[1] - s[1]];
  const ve: V2 = [e[0] - v[0], e[1] - v[1]];
  const lsv = Math.hypot(sv[0], sv[1]);
  const lve = Math.hypot(ve[0], ve[1]);
  if (lsv < 1e-6 || lve < 1e-6) return `M${s[0]},${s[1]} L${e[0]},${e[1]}`;
  const usv: V2 = [sv[0] / lsv, sv[1] / lsv];
  const uve: V2 = [ve[0] / lve, ve[1] / lve];
  const a1: V2 = [v[0] - usv[0] * r, v[1] - usv[1] * r];
  const a2: V2 = [v[0] + uve[0] * r, v[1] + uve[1] * r];
  const cross = usv[0] * uve[1] - usv[1] * uve[0];
  const sweep = cross < 0 ? 0 : 1;
  return `M${s[0]},${s[1]} L${a1[0].toFixed(3)},${a1[1].toFixed(3)} A${r},${r} 0 0 ${sweep} ${a2[0].toFixed(3)},${a2[1].toFixed(3)} L${e[0]},${e[1]}`;
}

export function CornerBracketsIcon({
  size = 14,
  color = "currentColor",
  strokeWidth,
  variant = "collapsed",
  className,
  style,
}: Props) {
  const lw = strokeWidth ?? 1.6;
  const t = variant === "expanded" ? 1 : 0;
  const lerp = (a: number, b: number) => a + (b - a) * t;

  const trS: V2 = [lerp(20, 14), lerp(9, 4)];
  const trV: V2 = [lerp(15, 20), lerp(9, 4)];
  const trE: V2 = [lerp(15, 20), lerp(4, 10)];
  const blS: V2 = [lerp(4, 10), lerp(15, 20)];
  const blV: V2 = [lerp(9, 4), lerp(15, 20)];
  const blE: V2 = [lerp(9, 4), lerp(20, 14)];
  const r = 2;

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
      <path d={corner(trS, trV, trE, r)} />
      <path d={corner(blS, blV, blE, r)} />
    </svg>
  );
}
