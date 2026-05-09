// InfoBanner mirror (SettingsKit.swift:147-191). Radius 9, semaphore fills
// (ok/error/danger), font 12 wght 600 (here bumped to 700 to match the
// Mac-side weight bump applied by BodyFont.swift).
import type { ReactNode } from "react";
import { CircleCheckIcon, TriangleAlertIcon, ShieldAlertIcon } from "../../icons";

type Kind = "ok" | "error" | "danger";

interface Props {
  kind: Kind;
  children: ReactNode;
}

const FILLS: Record<Kind, string> = {
  ok: "rgba(76,177,127,0.65)",
  error: "rgba(220,80,80,0.7)",
  danger: "rgba(228,142,77,0.7)",
};

export function InfoBanner({ kind, children }: Props) {
  const Icon = kind === "ok" ? CircleCheckIcon : kind === "error" ? TriangleAlertIcon : ShieldAlertIcon;
  return (
    <div
      className="flex items-center gap-2"
      style={{
        background: FILLS[kind],
        borderRadius: 9,
        padding: "9px 14px",
        color: "#fff",
      }}
    >
      <Icon size={13} className="text-white" />
      <div style={{ fontSize: 12, fontVariationSettings: '"wght" 700', lineHeight: 1.4 }}>
        {children}
      </div>
    </div>
  );
}
