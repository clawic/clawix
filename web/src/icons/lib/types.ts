// Shared shape for icon components. `size` is the pixel size of the icon's
// viewport (square unless the icon's design demands a different aspect, in
// which case the component declares its own).
import type { CSSProperties } from "react";

export interface IconProps {
  size?: number;
  color?: string;
  strokeWidth?: number;
  className?: string;
  style?: CSSProperties;
}
