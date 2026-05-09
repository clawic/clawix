// Mirror of SignOutIcon.swift: tall C on the left + arrow exiting right.
// 28-grid, r=3.5, h=0.5522847*r.
import type { IconProps } from "../lib/types";

const R = 3.5;
const H = 0.5522847 * R;

export function SignOutIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.5;
  const d =
    `M10.033,3.5 L7,3.5 ` +
    `C${(7 - H).toFixed(3)},3.5 3.5,${(7 - H).toFixed(3)} 3.5,7 ` +
    `L3.5,21 ` +
    `C3.5,${(21 + H).toFixed(3)} ${(7 - H).toFixed(3)},24.5 7,24.5 ` +
    `L10.033,24.5 ` +
    `M11.667,14 L23.333,14 ` +
    `M18.667,9.333 L23.333,14 L18.667,18.667`;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 28 28"
      fill="none"
      stroke={color}
      strokeWidth={lw}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={style}
    >
      <path d={d} />
    </svg>
  );
}
