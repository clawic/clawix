// Mirror of UsageIcon.swift: 270° gauge arc + filled needle.
import type { IconProps } from "../lib/types";

export function UsageIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.6;
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
      <path d="M5.64,18.36 C2.125,14.845 2.125,9.155 5.64,5.64 C9.155,2.125 14.845,2.125 18.36,5.64 C21.875,9.155 21.875,14.845 18.36,18.36" />
      <path
        d="M16.60,7.40 C17.02,8.38 14.40,12.99 13.70,13.70 C12.76,14.63 11.24,14.63 10.30,13.70 C9.37,12.76 9.37,11.24 10.30,10.30 C11.01,9.60 15.62,6.98 16.60,7.40 Z"
        fill={color}
        stroke="none"
      />
    </svg>
  );
}
