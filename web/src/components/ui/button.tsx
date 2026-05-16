// Sheet-style buttons mirroring SheetChrome.swift (Mac).
//   primary     -> SheetPrimaryButtonStyle (white solid, radius 10, 14x9, 13.5/wght 500)
//   cancel      -> SheetCancelButtonStyle (text + outline, hover white 18%)
//   destructive -> SheetDestructiveButtonStyle (#F26B6B, radius 9, 14x8, 13/wght 600)
import { ButtonHTMLAttributes, forwardRef } from "react";
import cx from "../../lib/cx";

type Variant = "primary" | "cancel" | "destructive";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
}

export const Button = forwardRef<HTMLButtonElement, Props>(function Button(
  { variant = "primary", className, children, disabled, ...rest },
  ref,
) {
  const base =
    "inline-flex items-center justify-center transition-[opacity,background,border-color] duration-[120ms] ease-[var(--ease-press)] disabled:cursor-not-allowed";
  const styles =
    variant === "primary"
      ? cx(
          "bg-white text-black rounded-[10px] px-[14px] py-[9px]",
          "active:bg-white/85",
          disabled && "opacity-45",
        )
      : variant === "cancel"
      ? cx(
          "rounded-[10px] px-[14px] py-[9px]",
          "border border-white/[0.13] hover:border-white/[0.18] hover:bg-white/[0.05]",
          "text-white/95 active:text-white/70",
        )
      : cx(
          "rounded-[9px] px-[14px] py-[8px]",
          "text-[var(--color-destructive)]",
          "hover:bg-[var(--color-destructive-fill)]",
          "active:opacity-75",
        );

  const fontStyle =
    variant === "destructive"
      ? { fontSize: 13, fontVariationSettings: '"wght" 700' }
      : { fontSize: 13.5, fontVariationSettings: '"wght" 600' };

  return (
    <button
      ref={ref}
      disabled={disabled}
      className={cx(base, styles, className)}
      style={fontStyle}
      {...rest}
    >
      {children}
    </button>
  );
});
