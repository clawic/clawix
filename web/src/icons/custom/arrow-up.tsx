// Mirror of ArrowUpIcon.swift: chevron with squircle-rounded apex on a
// 28-grid, tail extends to y=24.
import type { IconProps } from "../lib/types";

export function ArrowUpIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.5;
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
      <path d="M5,14 L12.5,6.5 C13.5,5.5 14.5,5.5 15.5,6.5 L23,14 M14,24 L14,5.75" />
    </svg>
  );
}
