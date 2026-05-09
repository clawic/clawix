// Tokens mirror the Mac palette
// (clawix/macos/Sources/Clawix/ContentView.swift -> enum Palette / enum MenuStyle).
// If a color changes here, compare it against the Mac palette first.
// Dark-only: the Mac app has no light mode, and neither does the web client.

export const tokens = {
  color: {
    bg: "#0a0a0a",
    sidebar: "#3e3e3e",
    cardFill: "#242424",
    cardHover: "#2b2b2b",
    border: "#333333",
    borderSubtle: "#262626",
    popupStroke: "rgba(255,255,255,0.10)",
    popupStrokeWidth: 0.5,
    selFill: "#474747",
    fg: "#ffffff",
    fgSecondary: "#8c8c8c",
    fgTertiary: "#616161",
    pastelBlue: "#73a6ff",
    menuFill: "rgba(34,34,34,0.82)",
    menuDivider: "rgba(255,255,255,0.06)",
    menuRowText: "#f0f0f0",
    menuRowIcon: "#dbdbdb",
    menuRowSubtle: "#8c8c8c",
    menuHeader: "#808080",
    toastFill: "rgba(29,29,29,0.92)",
    sheetFill: "rgba(26,26,26,0.78)",
    settingsCardFill: "#161616",
    hintFill: "#2e2e2e",
    hintStroke: "rgba(255,255,255,0.22)",
    cardSubtleDivider: "rgba(255,255,255,0.07)",
    destructive: "#f26b6b",
    destructiveFill: "rgba(242,107,107,0.14)",
    bannerOk: "rgba(76,177,127,0.18)",
    bannerOkFg: "#7fd0a3",
    bannerErr: "rgba(208,98,98,0.18)",
    bannerErrFg: "#e58a8a",
    bannerDanger: "rgba(228,142,77,0.18)",
    bannerDangerFg: "#eaa76d",
  },
  radius: {
    xs: 4,
    sm: 6,
    hint: 7,
    row: 8,
    banner: 9,
    card: 10,
    menu: 12,
    content: 14,
  },
  shadow: {
    menu: "0 10px 18px rgba(0,0,0,0.40)",
    sheet: "0 12px 22px rgba(0,0,0,0.40)",
    toast: "0 8px 18px rgba(0,0,0,0.34)",
    hint: "0 3px 8px rgba(0,0,0,0.30)",
  },
  smoothing: {
    apple: 0.6,
  },
  // Manrope variable (wght axis 200..800).
  // The Mac app bumps weights by one step so the UI reads more firmly:
  //   regular -> SemiBold (600), medium -> Bold (700), semibold+ -> ExtraBold (800).
  // Same bump on web.
  weight: {
    regular: 600,
    medium: 700,
    semibold: 800,
    bold: 800,
  },
  motion: {
    pressMs: 120,
    rowMs: 150,
    menuMs: 200,
    cardMs: 220,
    findMs: 180,
    sidebarMs: 200,
    rightSidebarMs: 280,
    toastSpringIn: { type: "spring" as const, stiffness: 420, damping: 38, mass: 0.85 },
    toastEaseOut: { duration: 0.22, ease: [0.4, 0, 1, 1] as const },
    easeOut: [0, 0, 0.2, 1] as const,
    easeInOut: [0.4, 0, 0.2, 1] as const,
    easeIn: [0.4, 0, 1, 1] as const,
  },
  type: {
    headlineTracking: "-0.02em",
    bodyTracking: "-0.01em",
    bodySize: 13.5,
    headerSize: 13,
    titleSize: 22,
    captionSize: 11,
  },
} as const;

export type Tokens = typeof tokens;
