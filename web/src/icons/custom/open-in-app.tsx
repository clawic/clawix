// Mirror of OpenInAppIcon.swift: open-corner squircle (BR cut) + small
// nested squircle in the missing corner + TL accent. 24-grid.
import type { IconProps } from "../lib/types";

// SVG arc helpers replacing the Swift addArc(center, radius, ...) calls.
function arc(cx: number, cy: number, r: number, _fromDeg: number, toDeg: number, sweep = 1): string {
  const rad = (toDeg * Math.PI) / 180;
  const tx = cx + r * Math.cos(rad);
  const ty = cy + r * Math.sin(rad);
  const delta = Math.abs(toDeg - _fromDeg);
  const large = delta > 180 ? 1 : 0;
  return `A${r},${r} 0 ${large} ${sweep} ${tx.toFixed(3)},${ty.toFixed(3)}`;
}

export function OpenInAppIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const lw = strokeWidth ?? 1.7;

  // Big squircle (open path): start (5.5,21.5), arc around (6.1,16.9) r=4.6
  // 97.49° → 180°, line up, arc TL 180→270, line right, arc TR 270→352.51.
  const big =
    `M5.5,21.5 ${arc(6.1, 16.9, 4.6, 97.49, 180)} ` +
    `L1.5,6.1 ${arc(6.1, 6.1, 4.6, 180, 270)} ` +
    `L16.9,1.5 ${arc(16.9, 6.1, 4.6, 270, 352.51)}`;

  // Small nested squircle (closed) at (9.7..21.5, 9.7..21.5), corner 3.
  const small = `M12.7,9.7 L18.5,9.7 ${arc(18.5, 12.7, 3, 270, 360)} L21.5,18.5 ${arc(18.5, 18.5, 3, 0, 90)} L12.7,21.5 ${arc(12.7, 18.5, 3, 90, 180)} L9.7,12.7 ${arc(12.7, 12.7, 3, 180, 270)} Z`;

  // TL accent: line down to vertex, quarter arc, line right.
  const accent = `M5.7,9 L5.7,7.2 ${arc(7.2, 7.2, 1.5, 180, 270)} L9,5.7`;

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
      <path d={big} />
      <path d={small} />
      <path d={accent} />
    </svg>
  );
}
