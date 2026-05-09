// SectionLabel mirror (SettingsKit.swift:32-42). 13/wght 800 (Mac .wght 600),
// padding-top 28, padding-bottom 14, leading 3.
import type { ReactNode } from "react";

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        fontSize: 13,
        fontVariationSettings: '"wght" 800',
        color: "var(--color-fg)",
        paddingTop: 28,
        paddingBottom: 14,
        paddingLeft: 3,
        letterSpacing: "-0.01em",
      }}
    >
      {children}
    </div>
  );
}
