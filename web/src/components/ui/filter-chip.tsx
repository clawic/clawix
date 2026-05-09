// FilterChip mirror (SettingsKit.swift:296-331). 26pt height, radius 13,
// soft active state.
import { ButtonHTMLAttributes, ReactNode, useState } from "react";
import cx from "../../lib/cx";

interface Props extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children"> {
  label: ReactNode;
  active: boolean;
}

export function FilterChip({ label, active, className, ...rest }: Props) {
  const [hovered, setHovered] = useState(false);
  const fillGray = active ? 0.20 + (hovered ? 0.02 : 0) : 0.135 + (hovered ? 0.03 : 0);
  const v = Math.round(fillGray * 255);
  return (
    <button
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      className={cx(
        "inline-flex items-center transition-[background-color,color] duration-[120ms] ease-[var(--ease-press)]",
        className,
      )}
      style={{
        height: 26,
        padding: "0 12px",
        borderRadius: 13,
        background: `rgb(${v}, ${v}, ${v})`,
        boxShadow: active ? "inset 0 0 0 0.5px rgba(255,255,255,0.10)" : undefined,
        color: active ? "var(--color-fg)" : "var(--color-fg-secondary)",
        fontSize: 11.5,
        fontVariationSettings: '"wght" 700',
      }}
      {...rest}
    >
      {label}
    </button>
  );
}
