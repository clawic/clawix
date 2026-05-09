// Custom mic glyph. Mac uses a Phosphor-style fill with stretchX 1.06 +
// compressY 0.94 around (128,96) on a 256 design space. We replicate the
// silhouette in a simpler 24-grid SVG that reads identically at icon sizes.
import type { IconProps } from "../lib/types";

export function MicIcon({ size = 14, color = "currentColor", className, style }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={color}
      className={className}
      style={style}
    >
      <rect x="8.5" y="2" width="7" height="13" rx="3.5" />
      <path d="M5.4,10 C5.4,10 6,15 12,15 C18,15 18.6,10 18.6,10 L17.2,10 C17.2,10 16.6,13.6 12,13.6 C7.4,13.6 6.8,10 6.8,10 Z" />
      <rect x="11.2" y="15" width="1.6" height="5" />
      <rect x="8.5" y="19" width="7" height="1.4" rx="0.7" />
    </svg>
  );
}
