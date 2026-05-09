// Mirror of FolderOpenIcon.swift: open folder outline on an 18-grid.
import type { IconProps } from "../lib/types";

export function FolderOpenIcon({ size = 13, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.5;
  return (
    <svg
      width={size * 1.18}
      height={size}
      viewBox="0 0 18 18"
      fill="none"
      stroke={color}
      strokeWidth={lw}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={style}
    >
      <path d="M3,15 L4.5,10.5 L5.625,8.324 C5.875,7.828 6.375,7.512 6.93,7.5 L15,7.5 C15.465,7.5 15.902,7.715 16.188,8.082 C16.473,8.449 16.57,8.926 16.453,9.375 L15.301,13.875 C15.129,14.539 14.523,15.004 13.836,15 L3,15 C2.172,15 1.5,14.328 1.5,13.5 L1.5,3.75 C1.5,2.922 2.172,2.25 3,2.25 L5.949,2.25 C6.449,2.254 6.918,2.508 7.191,2.926 L7.809,3.824 C8.082,4.242 8.551,4.496 9.051,4.5 L13.5,4.5 C14.328,4.5 15,5.172 15,6 L15,7.5" />
    </svg>
  );
}
