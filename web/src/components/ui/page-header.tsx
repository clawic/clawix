// PageHeader mirror (SettingsKit.swift:11-28). Title 22/wght 800 (Mac
// .semibold), optional subtitle 12.5 secondary fg, padding-bottom 26.
import type { ReactNode } from "react";

interface Props {
  title: ReactNode;
  subtitle?: ReactNode;
}

export function PageHeader({ title, subtitle }: Props) {
  return (
    <div className="flex flex-col gap-1.5" style={{ paddingBottom: 26 }}>
      <h1
        style={{
          fontSize: 22,
          fontVariationSettings: '"wght" 800',
          letterSpacing: "-0.02em",
          color: "var(--color-fg)",
        }}
      >
        {title}
      </h1>
      {subtitle && (
        <div
          style={{
            fontSize: 12.5,
            color: "var(--color-fg-secondary)",
            fontVariationSettings: '"wght" 600',
          }}
        >
          {subtitle}
        </div>
      )}
    </div>
  );
}
