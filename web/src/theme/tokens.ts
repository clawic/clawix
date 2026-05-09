export const tokens = {
  color: {
    bg: "#0c0c0e",
    bgElev1: "#131318",
    bgElev2: "#1a1a20",
    bgElev3: "#232329",
    fg: "#f3f3f5",
    fgMuted: "#a3a3ad",
    fgDim: "#6c6c78",
    border: "rgba(255, 255, 255, 0.08)",
    borderStrong: "rgba(255, 255, 255, 0.14)",
    accent: "#d4d4dc",
    danger: "#ff6464",
    success: "#5dd29c",
    warning: "#f5b95c",
  },
  radius: {
    xs: 6,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 22,
    xxl: 28,
  },
  smoothing: {
    /** figma-squircle smoothing factor that approximates Apple continuous corner. */
    apple: 0.6,
  },
  motion: {
    snappy: { duration: 0.32, ease: [0.16, 1, 0.3, 1] as const },
    smooth: { duration: 0.45, ease: [0.22, 1, 0.36, 1] as const },
    spring: { type: "spring" as const, stiffness: 420, damping: 38, mass: 0.85 },
  },
  type: {
    headlineTracking: "-0.02em",
    bodyTracking: "-0.01em",
  },
} as const;

export type Tokens = typeof tokens;
