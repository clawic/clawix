// Mirror of ExternalLinkIcon.swift: open squircle (TR open) + arrow exiting.
import type { IconProps } from "../lib/types";

export function ExternalLinkIcon({ size = 13, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.7;
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
      <path d="M20,14 C20,19 19,20 13,20 L11,20 C5,20 4,19 4,13 L4,11 C4,5 5,4 10,4 M13,11 L21,3 M15,3 L21,3 L21,9" />
    </svg>
  );
}
