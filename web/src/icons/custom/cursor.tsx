// Mirror of CursorIcon.swift: filled arrow cursor on a 28-grid.
import type { IconProps } from "../lib/types";

export function CursorIcon({ size = 14, color = "currentColor", className, style }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 28 28"
      fill={color}
      className={className}
      style={style}
    >
      <path d="M9.00,6.22 L19.28,9.74 Q23.52,11.20 19.43,13.01 L17.03,14.08 Q14.98,14.98 14.08,17.03 L13.01,19.43 Q11.20,23.52 9.74,19.28 L6.22,9.00 Q4.76,4.76 9.00,6.22 Z" />
    </svg>
  );
}
