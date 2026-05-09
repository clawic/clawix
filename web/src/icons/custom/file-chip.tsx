// Mirror of FileChipIcon.swift: page outline with rounded corners + folded
// top-right corner + two interior horizontal rules. 26x28 viewBox.
import type { IconProps } from "../lib/types";

export function FileChipIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.8;
  // Approximation of the addArc-tangent layout via line + quadratic curves
  // placed at the same anchors. Large radii (4-5) match the Mac geometry.
  return (
    <svg
      width={(size * 26) / 28}
      height={size}
      viewBox="0 0 26 28"
      fill="none"
      stroke={color}
      strokeWidth={lw}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={style}
    >
      <path d="M7,1 L17,1 Q24,1 24,8 L24,26 Q24,26 2,26 Q2,26 2,1 Q2,1 7,1 Z" />
      <path d="M7.5,11 L15,11" />
      <path d="M7.5,17.5 L11.5,17.5" />
    </svg>
  );
}
