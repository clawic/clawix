// Mirror of McpIcon.swift: three interlocking hooks (Model Context Protocol).
import type { IconProps } from "../lib/types";

export function McpIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
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
      <path d="M3.09,7.29 L5.92,4.46 C9.31,1.07 16.09,7.85 12.70,11.24 L9.87,14.07" />
      <path d="M9.98,13.99 L12.81,11.16 C16.20,7.77 22.98,14.55 19.59,17.94 L16.76,20.77" />
      <path d="M7.25,9.92 L4.42,12.75 C1.03,16.14 7.81,22.92 11.20,19.53 L14.03,16.70" />
    </svg>
  );
}
