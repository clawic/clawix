// IconChipButton mirror (SettingsKit.swift:200-258). Capsule, 28pt height,
// dark fill that bumps on hover, optional label. isPrimary raises resting fill.
import { ButtonHTMLAttributes, ReactNode, useState } from "react";
import cx from "../../lib/cx";

interface Props extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children"> {
  icon: ReactNode;
  label?: ReactNode;
  isPrimary?: boolean;
}

export function IconChipButton({ icon, label, isPrimary, className, ...rest }: Props) {
  const [hovered, setHovered] = useState(false);
  const baseGray = isPrimary ? 0.165 : 0.135;
  const lift = hovered ? 0.03 : 0;
  const v = Math.round((baseGray + lift) * 255);
  return (
    <button
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      className={cx(
        "inline-flex items-center gap-1.5 transition-[background-color] duration-[120ms] ease-[var(--ease-press)]",
        className,
      )}
      style={{
        height: 28,
        padding: label ? "0 11px" : "0 9px",
        borderRadius: 999,
        background: `rgb(${v}, ${v}, ${v})`,
        boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.10)",
        color: "var(--color-fg)",
      }}
      {...rest}
    >
      <span style={{ display: "inline-flex" }}>{icon}</span>
      {label && (
        <span style={{ fontSize: 12, fontVariationSettings: '"wght" 700' }}>{label}</span>
      )}
    </button>
  );
}
