// Mirror of WrenchIcon.swift: wrench gripping a hex bolt, 24-grid.
import type { IconProps } from "../lib/types";

const D =
  "M14.7,6.3 " +
  "C14.306,6.687 14.306,7.313 14.7,7.7 " +
  "L16.3,9.3 " +
  "C16.694,9.687 17.306,9.687 17.7,9.3 " +
  "L20.806,6.195 " +
  "C21.126,5.873 21.669,5.975 21.789,6.413 " +
  "C22.405,8.661 21.662,11.062 19.886,12.572 " +
  "C18.110,14.082 15.649,14.440 13.53,13.47 " +
  "L5.62,21.38 " +
  "C4.7916,22.2084 3.4489,22.2084 2.6205,21.38 " +
  "C1.7921,20.5516 1.7926,19.2084 2.621,18.38 " +
  "L10.531,10.47 " +
  "C9.572,8.346 9.925,5.872 11.440,4.100 " +
  "C12.955,2.328 15.339,1.598 17.588,2.211 " +
  "C18.026,2.331 18.128,2.873 17.807,3.195 " +
  "Z";

export function WrenchIcon({ size = 16, color = "currentColor", strokeWidth, className, style }: IconProps) {
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
      <path d={D} />
    </svg>
  );
}
