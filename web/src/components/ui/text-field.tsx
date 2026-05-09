// SheetTextFieldStyle mirror (SheetChrome.swift:102-119). 14px font wght 500
// (web bump 700), padding 11x14, radius 10, fill white 6%, stroke 10%.
import { InputHTMLAttributes, forwardRef } from "react";
import cx from "../../lib/cx";

export const TextField = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  function TextField({ className, style, ...rest }, ref) {
    return (
      <input
        ref={ref}
        className={cx("outline-none w-full", className)}
        style={{
          padding: "11px 14px",
          borderRadius: 10,
          background: "rgba(255,255,255,0.06)",
          boxShadow: "inset 0 0 0 0.6px rgba(255,255,255,0.10)",
          color: "rgba(255,255,255,0.96)",
          fontSize: 14,
          fontVariationSettings: '"wght" 700',
          ...style,
        }}
        {...rest}
      />
    );
  },
);
