/**
 * Squircle wrapper. Uses figma-squircle for SVG-based path rendering on
 * components with large radius (≥16px). For smaller radii the difference
 * vs `border-radius` is imperceptible, so the variant `simple` falls back
 * to a plain DOM box with `border-radius`.
 */
import { CSSProperties, ReactNode, useMemo } from "react";
import { getSvgPath } from "figma-squircle";
import { tokens } from "../theme/tokens";

export interface SquircleProps {
  width?: number | string;
  height?: number | string;
  radius?: number;
  smoothing?: number;
  background?: string;
  border?: string;
  borderWidth?: number;
  shadow?: string;
  className?: string;
  style?: CSSProperties;
  children?: ReactNode;
  onClick?: () => void;
  /** When true, renders a SVG-clipped squircle. False uses CSS border-radius (cheaper). */
  exact?: boolean;
}

/**
 * For small radii (<= 12) the visual difference is sub-pixel. Render a
 * plain rounded box. For larger radii we mask the box with a squircle SVG
 * path so the iconic Apple continuous-corner is preserved.
 */
export function Squircle(props: SquircleProps) {
  const {
    width,
    height,
    radius = tokens.radius.content,
    smoothing = tokens.smoothing.apple,
    background,
    border,
    borderWidth = 1,
    shadow,
    className,
    style,
    children,
    onClick,
    exact,
  } = props;

  const useExact = exact ?? radius >= 16;

  const clipPath = useMemo(() => {
    if (!useExact || typeof width !== "number" || typeof height !== "number") return undefined;
    const path = getSvgPath({
      width,
      height,
      cornerRadius: radius,
      cornerSmoothing: smoothing,
    });
    return `path("${path}")`;
  }, [useExact, width, height, radius, smoothing]);

  const finalStyle: CSSProperties = {
    width,
    height,
    background,
    boxShadow: shadow,
    border,
    borderWidth,
    borderStyle: border ? "solid" : undefined,
    borderRadius: useExact && clipPath ? undefined : radius,
    clipPath,
    ...style,
  };

  return (
    <div className={className} style={finalStyle} onClick={onClick}>
      {children}
    </div>
  );
}
