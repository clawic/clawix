// Mirror of StopIcon.swift StopSquircle: superellipse n=5 (Apple app-icon mask).
import { useMemo } from "react";
import { superellipsePath } from "../lib/squircle-path";
import type { IconProps } from "../lib/types";

export function StopSquircle({ size = 14, color = "currentColor", className, style }: IconProps) {
  const d = useMemo(() => superellipsePath(24, 24, 5, 96), []);
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={color}
      className={className}
      style={style}
    >
      <path d={d} />
    </svg>
  );
}
