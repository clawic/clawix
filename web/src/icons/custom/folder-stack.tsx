// Mirror of FolderStackIcon.swift: two stacked folders, only the front
// silhouette is closed, back has an L-shape (no bottom-left).
import type { IconProps } from "../lib/types";

export function FolderStackIcon({ size = 13, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.7;
  return (
    <svg
      width={size * 1.05}
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
      <path d="M9,3.5 L11.7,3.5 C12.2,3.5 12.42,3.6 12.5,3.9 L13.2,4.8 C13.35,5.1 13.7,5.2 14,5.2 L20,5.2 C20.828,5.2 21.5,5.872 21.5,6.7 L21.5,13 C21.5,13.828 20.828,14.5 20,14.5" />
      <path d="M2.5,17.5 L2.5,8 C2.5,7.172 3.172,6.5 4,6.5 L7.2,6.5 C7.7,6.5 7.92,6.6 8,6.9 L8.9,8.1 C9.05,8.4 9.4,8.5 9.7,8.5 L16.5,8.5 C17.328,8.5 18,9.172 18,10 L18,17.5 C18,18.328 17.328,19 16.5,19 L4,19 C3.172,19 2.5,18.328 2.5,17.5 Z" />
    </svg>
  );
}
