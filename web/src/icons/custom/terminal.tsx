// Mirror of TerminalIcon.swift: squircle frame + chevron + line.
import type { IconProps } from "../lib/types";

export function TerminalIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 2.0;
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
      <rect x="2" y="2" width="24" height="24" rx="6" ry="6" />
      <path d="M8,11 L11,14 L8,17 M16,17 L20,17" />
    </svg>
  );
}
