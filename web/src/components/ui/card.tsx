// SettingsCard mirror (SettingsKit.swift:46-62).
// Continuous corner radius 10, fill #161616 (white 0.085), hairline stroke
// rgba(255,255,255,0.10) 0.5px.
import type { HTMLAttributes, ReactNode } from "react";
import cx from "../../lib/cx";

interface Props extends HTMLAttributes<HTMLDivElement> {
  children?: ReactNode;
}

export function Card({ className, children, ...rest }: Props) {
  return (
    <div
      className={cx("relative", className)}
      style={{
        background: "var(--color-settings-card)",
        borderRadius: 10,
        boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.10)",
      }}
      {...rest}
    >
      {children}
    </div>
  );
}

export function CardDivider() {
  return <div style={{ height: 1, background: "var(--color-card-divider)" }} />;
}
