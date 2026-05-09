// Mirror of CheckIcon.swift: tick with continuous-corner elbow.
// 24-grid, anchors (20,6) → (~9.99,16.01) → (4,12).
import type { IconProps } from "../lib/types";

export function CheckIcon({ size = 16, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.0;
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
      <path d="M20,6 L9.99,16.01 C9.64,16.36 9.47,16.54 9.26,16.60 C9.09,16.66 8.91,16.66 8.74,16.60 C8.53,16.54 8.36,16.36 8.01,16.01 L4,12" />
    </svg>
  );
}
