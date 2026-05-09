// Mirror of BotIcon.swift: stroked iOS-squircle body + antenna, plus filled
// ear/eye pills. 24-grid. Body squircle E=6 on a 20x15 box at (2,7).
import type { IconProps } from "../lib/types";

const BODY_PATH =
  "M8,7 L16,7 " +
  "C18.118,7 19.18,7 19.99,7.414 " +
  "C20.692,7.774 21.226,8.308 21.586,9.01 " +
  "C22,9.82 22,10.882 22,13 " +
  "L22,16 " +
  "C22,18.118 22,19.18 21.586,19.99 " +
  "C21.226,20.692 20.692,21.226 19.99,21.586 " +
  "C19.18,22 18.118,22 16,22 " +
  "L8,22 " +
  "C5.882,22 4.82,22 4.01,21.586 " +
  "C3.308,21.226 2.774,20.692 2.414,19.99 " +
  "C2,19.18 2,18.118 2,16 " +
  "L2,13 " +
  "C2,10.882 2,9.82 2.414,9.01 " +
  "C2.774,8.308 3.308,7.774 4.01,7.414 " +
  "C4.82,7 5.882,7 8,7 Z " +
  "M12,7 L12,4 " +
  "C12,3.647 12,3.470 11.931,3.335 " +
  "C11.871,3.218 11.782,3.129 11.665,3.069 " +
  "C11.530,3 11.353,3 11,3 L8,3";

// Filled features: 2 ear pills (2x1) + 2 eye pills (1.6x3).
function ear(ox: number, oy: number) {
  return (
    `M${ox + 0.5},${oy} L${ox + 1.5},${oy} ` +
    `C${ox + 1.677},${oy} ${ox + 1.765},${oy} ${ox + 1.833},${oy + 0.035} ` +
    `C${ox + 1.891},${oy + 0.065} ${ox + 1.936},${oy + 0.109} ${ox + 1.966},${oy + 0.168} ` +
    `C${ox + 2},${oy + 0.235} ${ox + 2},${oy + 0.324} ${ox + 2},${oy + 0.5} ` +
    `C${ox + 2},${oy + 0.677} ${ox + 2},${oy + 0.765} ${ox + 1.966},${oy + 0.833} ` +
    `C${ox + 1.936},${oy + 0.891} ${ox + 1.891},${oy + 0.936} ${ox + 1.833},${oy + 0.966} ` +
    `C${ox + 1.765},${oy + 1} ${ox + 1.677},${oy + 1} ${ox + 1.5},${oy + 1} ` +
    `L${ox + 0.5},${oy + 1} ` +
    `C${ox + 0.324},${oy + 1} ${ox + 0.235},${oy + 1} ${ox + 0.168},${oy + 0.966} ` +
    `C${ox + 0.109},${oy + 0.936} ${ox + 0.065},${oy + 0.891} ${ox + 0.035},${oy + 0.833} ` +
    `C${ox},${oy + 0.765} ${ox},${oy + 0.677} ${ox},${oy + 0.5} ` +
    `C${ox},${oy + 0.324} ${ox},${oy + 0.235} ${ox + 0.035},${oy + 0.168} ` +
    `C${ox + 0.065},${oy + 0.109} ${ox + 0.109},${oy + 0.065} ${ox + 0.168},${oy + 0.035} ` +
    `C${ox + 0.235},${oy} ${ox + 0.324},${oy} ${ox + 0.5},${oy} Z`
  );
}
function eye(ox: number, oy: number) {
  return (
    `M${ox + 0.8},${oy} ` +
    `C${ox + 1.082},${oy} ${ox + 1.224},${oy} ${ox + 1.332},${oy + 0.055} ` +
    `C${ox + 1.426},${oy + 0.103} ${ox + 1.497},${oy + 0.174} ${ox + 1.545},${oy + 0.268} ` +
    `C${ox + 1.6},${oy + 0.376} ${ox + 1.6},${oy + 0.518} ${ox + 1.6},${oy + 0.8} ` +
    `L${ox + 1.6},${oy + 2.2} ` +
    `C${ox + 1.6},${oy + 2.482} ${ox + 1.6},${oy + 2.624} ${ox + 1.545},${oy + 2.732} ` +
    `C${ox + 1.497},${oy + 2.826} ${ox + 1.426},${oy + 2.897} ${ox + 1.332},${oy + 2.945} ` +
    `C${ox + 1.224},${oy + 3} ${ox + 1.082},${oy + 3} ${ox + 0.8},${oy + 3} ` +
    `C${ox + 0.518},${oy + 3} ${ox + 0.376},${oy + 3} ${ox + 0.268},${oy + 2.945} ` +
    `C${ox + 0.174},${oy + 2.897} ${ox + 0.103},${oy + 2.826} ${ox + 0.055},${oy + 2.732} ` +
    `C${ox},${oy + 2.624} ${ox},${oy + 2.482} ${ox},${oy + 2.2} ` +
    `L${ox},${oy + 0.8} ` +
    `C${ox},${oy + 0.518} ${ox},${oy + 0.376} ${ox + 0.055},${oy + 0.268} ` +
    `C${ox + 0.103},${oy + 0.174} ${ox + 0.174},${oy + 0.103} ${ox + 0.268},${oy + 0.055} ` +
    `C${ox + 0.376},${oy} ${ox + 0.518},${oy} ${ox + 0.8},${oy} Z`
  );
}

const FILL_PATH = `${ear(0, 14)} ${ear(22, 14)} ${eye(7.7, 13.5)} ${eye(14.7, 12.5)}`;

export function BotIcon({ size = 16, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.4;
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
      <path d={BODY_PATH} />
      <path d={FILL_PATH} fill={color} stroke="none" />
    </svg>
  );
}
