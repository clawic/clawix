/**
 * Glass pill. Replicates the macOS "glass distorting button" look the user
 * expects on chrome floating over content: backdrop blur, alpha background,
 * thin white border, soft shadow.
 */
import { ButtonHTMLAttributes, ReactNode } from "react";
import clsx from "../lib/cx";

export interface GlassPillProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  size?: "sm" | "md" | "lg";
  variant?: "dark" | "light";
}

export function GlassPill({ children, size = "md", variant = "dark", className, ...rest }: GlassPillProps) {
  return (
    <button
      type="button"
      className={clsx(
        "glass-pill inline-flex items-center justify-center gap-1.5 select-none transition-[transform,opacity] active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none",
        size === "sm" && "h-8 px-3 text-[12px] rounded-full",
        size === "md" && "h-10 px-4 text-[13px] rounded-full",
        size === "lg" && "h-12 px-5 text-[14px] rounded-full",
        variant === "light" && "[background:rgba(255,255,255,0.65)] [border:1px_solid_rgba(0,0,0,0.06)] text-[var(--color-bg)]",
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
}
