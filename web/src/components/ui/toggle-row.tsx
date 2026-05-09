// ToggleRow mirror (SettingsKit.swift:97-110): label/detail on the left,
// PillToggle on the right, padding 14 horizontal / 12 vertical.
import type { ReactNode } from "react";
import { PillToggle } from "./pill-toggle";

interface Props {
  title: ReactNode;
  detail?: ReactNode;
  isOn: boolean;
  onChange: (next: boolean) => void;
}

export function ToggleRow({ title, detail, isOn, onChange }: Props) {
  return (
    <div className="flex items-center gap-3.5" style={{ padding: "12px 14px" }}>
      <div className="flex-1 min-w-0 flex flex-col gap-[3px]">
        <div style={{ fontSize: 12.5, color: "var(--color-fg)" }}>{title}</div>
        {detail && (
          <div
            style={{
              fontSize: 11,
              color: "var(--color-fg-secondary)",
              fontVariationSettings: '"wght" 700',
              lineHeight: 1.4,
            }}
          >
            {detail}
          </div>
        )}
      </div>
      <PillToggle isOn={isOn} onChange={onChange} />
    </div>
  );
}
