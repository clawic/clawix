// Mirror of LocalModelsIcon.swift: squircle CPU + 8 stub pins.
import type { IconProps } from "../lib/types";

export function LocalModelsIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.4;
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
      <path d="M6,12 C6,7.1 7.1,6 12,6 C16.9,6 18,7.1 18,12 C18,16.9 16.9,18 12,18 C7.1,18 6,16.9 6,12 Z" />
      <path d="M9,2 L9,6 M15,2 L15,6 M9,18 L9,22 M15,18 L15,22 M2,9 L6,9 M2,15 L6,15 M18,9 L22,9 M18,15 L22,15" />
    </svg>
  );
}
