// Mirror of GlobeIcon.swift: planet outline + equator + central meridian.
import type { IconProps } from "../lib/types";

export function GlobeIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
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
      <circle cx="14" cy="14" r="12" />
      <path d="M2,14 L26,14" />
      <ellipse cx="14" cy="14" rx="4.5" ry="12" />
    </svg>
  );
}
