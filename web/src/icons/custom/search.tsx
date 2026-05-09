// Mirror of SearchIcon.swift: magnifying glass on a 28-grid.
import type { IconProps } from "../lib/types";

export function SearchIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 3.15;
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
      <circle cx="13.03" cy="13.03" r="10.5" />
      <path d="M20.46,20.46 L26.85,26.85" />
    </svg>
  );
}
